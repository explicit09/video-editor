import Foundation

// MARK: - Command Protocol

@MainActor
public protocol Command: Sendable {
    var name: String { get }
    var affectedClipIDs: [UUID] { get }
    var affectedTrackIDs: [UUID] { get }
    var metadata: [String: String] { get }
    mutating func execute(context: EditingContext) throws
    func undo(context: EditingContext) throws
}

// Defaults so existing commands don't all need boilerplate
public extension Command {
    var affectedClipIDs: [UUID] { [] }
    var affectedTrackIDs: [UUID] { [] }
    var metadata: [String: String] { [:] }
}

// MARK: - EditingContext (DI container — no singletons)
// Single source of truth. Commands mutate timelineState directly.

@MainActor
public final class EditingContext: Sendable {
    public let timelineState: TimelineState
    public let media: MediaManager
    public let actionLog: ActionLog

    public init(
        timelineState: TimelineState = TimelineState(),
        media: MediaManager = MediaManager(),
        actionLog: ActionLog = ActionLog()
    ) {
        self.timelineState = timelineState
        self.media = media
        self.actionLog = actionLog
    }
}

// MARK: - CommandHistory

@MainActor @Observable
public final class CommandHistory {
    public private(set) var canUndo = false
    public private(set) var canRedo = false

    private struct StackEntry {
        var command: any Command
        var source: ActionSource
    }

    private var undoStack: [StackEntry] = []
    private var redoStack: [StackEntry] = []

    public init() {}

    /// Reset undo/redo stacks (used when switching projects).
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }

    public func execute(_ command: inout some Command, context: EditingContext, source: ActionSource = .user) throws {
        try command.execute(context: context)
        let recorded = command
        undoStack.append(StackEntry(command: recorded, source: source))
        redoStack.removeAll()
        logCommand(recorded, source: source, context: context)
        updateState()
    }

    public func undo(context: EditingContext) throws {
        guard var entry = undoStack.popLast() else { return }
        try entry.command.undo(context: context)
        redoStack.append(entry)
        logCommand(entry.command, source: .undo, context: context)
        updateState()
    }

    /// Undo only the most recent AI action, skipping user actions.
    public func undoLastAIAction(context: EditingContext) throws {
        // Find the last AI entry
        guard let idx = undoStack.lastIndex(where: { $0.source == .ai }) else { return }

        // Undo all entries from idx to end (in reverse)
        var toRedo: [StackEntry] = []
        while undoStack.count > idx {
            guard var entry = undoStack.popLast() else { break }
            if entry.source == .ai && toRedo.isEmpty {
                // This is the AI action — undo it
                try entry.command.undo(context: context)
                redoStack.append(entry)
                logCommand(entry.command, source: .undo, context: context)
            } else {
                // User action after the AI action — undo and re-apply later
                try entry.command.undo(context: context)
                toRedo.append(entry)
            }
        }

        // Re-apply user actions that were undone
        for var entry in toRedo.reversed() {
            try entry.command.execute(context: context)
            undoStack.append(entry)
        }

        updateState()
    }

    public func redo(context: EditingContext) throws {
        guard var entry = redoStack.popLast() else { return }
        try entry.command.execute(context: context)
        undoStack.append(entry)
        logCommand(entry.command, source: .redo, context: context)
        updateState()
    }

    private func logCommand(_ command: some Command, source: ActionSource, context: EditingContext) {
        let log = context.actionLog
        let name = command.name
        let clipIDs = command.affectedClipIDs
        let trackIDs = command.affectedTrackIDs
        let params = command.metadata
        Task { await log.record(commandName: name, clipIDs: clipIDs, trackIDs: trackIDs, parameters: params, source: source) }
    }

    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

// MARK: - BatchCommand

public struct BatchCommand: Command {
    public let name: String
    public var commands: [any Command]

    public init(name: String = "Batch", commands: [any Command]) {
        self.name = name
        self.commands = commands
    }

    public mutating func execute(context: EditingContext) throws {
        for i in commands.indices {
            do {
                try commands[i].execute(context: context)
            } catch {
                // Rollback: undo commands 0..<i in reverse
                for j in (0..<i).reversed() {
                    try? commands[j].undo(context: context)
                }
                throw error
            }
        }
    }

    public func undo(context: EditingContext) throws {
        for command in commands.reversed() {
            try command.undo(context: context)
        }
    }
}
