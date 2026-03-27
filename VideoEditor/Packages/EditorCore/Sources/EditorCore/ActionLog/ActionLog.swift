import Foundation

// MARK: - ActionEvent

public struct ActionEvent: Codable, Sendable {
    public let timestamp: Date
    public let commandName: String
    public let clipIDs: [UUID]
    public let trackIDs: [UUID]
    public let parameters: [String: String]
    public let source: ActionSource

    public init(
        timestamp: Date = Date(),
        commandName: String,
        clipIDs: [UUID] = [],
        trackIDs: [UUID] = [],
        parameters: [String: String] = [:],
        source: ActionSource
    ) {
        self.timestamp = timestamp
        self.commandName = commandName
        self.clipIDs = clipIDs
        self.trackIDs = trackIDs
        self.parameters = parameters
        self.source = source
    }
}

// MARK: - ActionSource

public enum ActionSource: String, Codable, Sendable {
    case user
    case ai
    case macro
    case undo
    case redo
}

// MARK: - ActionLog (actor — persists to SQLite in project bundle)

public actor ActionLog {
    private var events: [ActionEvent] = []

    public init() {}

    public func record(_ command: some Command, source: ActionSource) {
        let event = ActionEvent(commandName: command.name, source: source)
        events.append(event)
    }

    public func recentActions(count: Int) -> [ActionEvent] {
        Array(events.suffix(count))
    }

    public func actionsFor(clip clipID: UUID) -> [ActionEvent] {
        events.filter { $0.clipIDs.contains(clipID) }
    }

    public func actionsSince(_ date: Date) -> [ActionEvent] {
        events.filter { $0.timestamp >= date }
    }

    public func allEvents() -> [ActionEvent] {
        events
    }
}
