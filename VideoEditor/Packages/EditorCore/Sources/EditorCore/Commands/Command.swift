import Foundation

// MARK: - Command Protocol

public protocol Command: Sendable {
    var name: String { get }
    mutating func execute(context: EditingContext) throws
    func undo(context: EditingContext) throws
}

// MARK: - EditingContext (DI container — no singletons)

public final class EditingContext: Sendable {
    public let timeline: TimelineManager
    public let media: MediaManager
    public let projectStore: ProjectStore
    public let actionLog: ActionLog

    public init(
        timeline: TimelineManager,
        media: MediaManager,
        projectStore: ProjectStore,
        actionLog: ActionLog
    ) {
        self.timeline = timeline
        self.media = media
        self.projectStore = projectStore
        self.actionLog = actionLog
    }

    /// Convenience initializer — creates fresh instances for a new project.
    public convenience init() {
        self.init(
            timeline: TimelineManager(),
            media: MediaManager(),
            projectStore: ProjectStore(),
            actionLog: ActionLog()
        )
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
        Task { await log.record(recorded, source: .user) }
        updateState()
    }

    public func undo(context: EditingContext) throws {
        guard var command = undoStack.popLast() else { return }
        try command.undo(context: context)
        redoStack.append(command)
        let log = context.actionLog
        let recorded = command
        Task { await log.record(recorded, source: .undo) }
        updateState()
    }

    public func redo(context: EditingContext) throws {
        guard var command = redoStack.popLast() else { return }
        try command.execute(context: context)
        undoStack.append(command)
        let log = context.actionLog
        let recorded = command
        Task { await log.record(recorded, source: .redo) }
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

