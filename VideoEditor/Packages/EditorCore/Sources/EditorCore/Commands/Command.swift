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

    private var undoStack: [any Command] = []
    private var redoStack: [any Command] = []

    public init() {}

    public func execute(_ command: inout some Command, context: EditingContext, source: ActionSource = .user) throws {
        try command.execute(context: context)
        let recorded = command
        undoStack.append(recorded)
        redoStack.removeAll()
        logCommand(recorded, source: source, context: context)
        updateState()
    }

    public func undo(context: EditingContext) throws {
        guard var command = undoStack.popLast() else { return }
        try command.undo(context: context)
        let recorded = command
        redoStack.append(recorded)
        logCommand(recorded, source: .undo, context: context)
        updateState()
    }

    public func redo(context: EditingContext) throws {
        guard var command = redoStack.popLast() else { return }
        try command.execute(context: context)
        let recorded = command
        undoStack.append(recorded)
        logCommand(recorded, source: .redo, context: context)
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
            try commands[i].execute(context: context)
        }
    }

    public func undo(context: EditingContext) throws {
        for command in commands.reversed() {
            try command.undo(context: context)
        }
    }
}
