import Foundation

// MARK: - Command Protocol

@MainActor
public protocol Command: Sendable {
    var name: String { get }
    mutating func execute(context: EditingContext) throws
    func undo(context: EditingContext) throws
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

@MainActor
public final class CommandHistory: ObservableObject {
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    private var undoStack: [any Command] = []
    private var redoStack: [any Command] = []

    public init() {}

    public func execute(_ command: inout some Command, context: EditingContext) throws {
        try command.execute(context: context)
        let recorded = command
        undoStack.append(recorded)
        redoStack.removeAll()
        let log = context.actionLog
        let cmdName = recorded.name
        Task { await log.record(commandName: cmdName, source: .user) }
        updateState()
    }

    public func undo(context: EditingContext) throws {
        guard var command = undoStack.popLast() else { return }
        try command.undo(context: context)
        let recorded = command
        redoStack.append(recorded)
        let log = context.actionLog
        let cmdName = recorded.name
        Task { await log.record(commandName: cmdName, source: .undo) }
        updateState()
    }

    public func redo(context: EditingContext) throws {
        guard var command = redoStack.popLast() else { return }
        try command.execute(context: context)
        let recorded = command
        undoStack.append(recorded)
        let log = context.actionLog
        let cmdName = recorded.name
        Task { await log.record(commandName: cmdName, source: .redo) }
        updateState()
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
