import Foundation

// MARK: - ActionEvent

public struct ActionEvent: Codable, Sendable {
    public let id: Int?
    public let timestamp: Date
    public let commandName: String
    public let clipIDs: [UUID]
    public let trackIDs: [UUID]
    public let parameters: [String: String]
    public let source: ActionSource

    public init(
        id: Int? = nil,
        timestamp: Date = Date(),
        commandName: String,
        clipIDs: [UUID] = [],
        trackIDs: [UUID] = [],
        parameters: [String: String] = [:],
        source: ActionSource
    ) {
        self.id = id
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

// MARK: - ActionLog (actor — persists to SQLite)

public actor ActionLog {
    private var db: SQLiteDatabase?
    private var inMemoryFallback: [ActionEvent] = []

    public init() {}

    /// Open SQLite database at the given path. Call this when project bundle is known.
    public func open(at path: String) throws {
        let database = try SQLiteDatabase(path: path)
        try database.run("""
            CREATE TABLE IF NOT EXISTS action_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                command_name TEXT NOT NULL,
                clip_ids TEXT NOT NULL DEFAULT '[]',
                track_ids TEXT NOT NULL DEFAULT '[]',
                parameters TEXT NOT NULL DEFAULT '{}',
                source TEXT NOT NULL
            )
        """)
        try database.run("""
            CREATE INDEX IF NOT EXISTS idx_action_events_timestamp ON action_events(timestamp)
        """)
        try database.run("""
            CREATE INDEX IF NOT EXISTS idx_action_events_command ON action_events(command_name)
        """)
        self.db = database

        // Flush any in-memory events that were recorded before db was opened
        for event in inMemoryFallback {
            try? insertEvent(event)
        }
        inMemoryFallback.removeAll()
    }

    public func record(
        commandName: String,
        clipIDs: [UUID] = [],
        trackIDs: [UUID] = [],
        parameters: [String: String] = [:],
        source: ActionSource
    ) {
        let event = ActionEvent(
            commandName: commandName,
            clipIDs: clipIDs,
            trackIDs: trackIDs,
            parameters: parameters,
            source: source
        )

        if db != nil {
            try? insertEvent(event)
        } else {
            inMemoryFallback.append(event)
        }
    }

    public func recentActions(count: Int) -> [ActionEvent] {
        guard let db else { return Array(inMemoryFallback.suffix(count)) }
        let rows = (try? db.query(
            "SELECT * FROM action_events ORDER BY id DESC LIMIT ?",
            params: [.int(count)]
        )) ?? []
        return rows.reversed().map(Self.rowToEvent)
    }

    public func actionsFor(clip clipID: UUID) -> [ActionEvent] {
        let idStr = clipID.uuidString
        guard let db else { return inMemoryFallback.filter { $0.clipIDs.contains(clipID) } }
        let rows = (try? db.query(
            "SELECT * FROM action_events WHERE clip_ids LIKE ? ORDER BY id",
            params: [.text("%\(idStr)%")]
        )) ?? []
        return rows.map(Self.rowToEvent)
    }

    public func actionsSince(_ date: Date) -> [ActionEvent] {
        let ts = date.timeIntervalSince1970
        guard let db else { return inMemoryFallback.filter { $0.timestamp >= date } }
        let rows = (try? db.query(
            "SELECT * FROM action_events WHERE timestamp >= ? ORDER BY id",
            params: [.double(ts)]
        )) ?? []
        return rows.map(Self.rowToEvent)
    }

    public func allEvents() -> [ActionEvent] {
        guard let db else { return inMemoryFallback }
        let rows = (try? db.query("SELECT * FROM action_events ORDER BY id")) ?? []
        return rows.map(Self.rowToEvent)
    }

    public func eventCount() -> Int {
        guard let db else { return inMemoryFallback.count }
        let rows = (try? db.query("SELECT COUNT(*) as cnt FROM action_events")) ?? []
        return rows.first?["cnt"]?.intValue ?? 0
    }

    // MARK: - Private

    private func insertEvent(_ event: ActionEvent) throws {
        let clipIDsJSON = Self.encodeUUIDs(event.clipIDs)
        let trackIDsJSON = Self.encodeUUIDs(event.trackIDs)
        let paramsJSON = Self.encodeParams(event.parameters)

        try db?.run(
            """
            INSERT INTO action_events (timestamp, command_name, clip_ids, track_ids, parameters, source)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            params: [
                .double(event.timestamp.timeIntervalSince1970),
                .text(event.commandName),
                .text(clipIDsJSON),
                .text(trackIDsJSON),
                .text(paramsJSON),
                .text(event.source.rawValue),
            ]
        )
    }

    private static func rowToEvent(_ row: [String: SQLiteValue]) -> ActionEvent {
        ActionEvent(
            id: row["id"]?.intValue,
            timestamp: Date(timeIntervalSince1970: row["timestamp"]?.doubleValue ?? 0),
            commandName: row["command_name"]?.textValue ?? "",
            clipIDs: decodeUUIDs(row["clip_ids"]?.textValue ?? "[]"),
            trackIDs: decodeUUIDs(row["track_ids"]?.textValue ?? "[]"),
            parameters: decodeParams(row["parameters"]?.textValue ?? "{}"),
            source: ActionSource(rawValue: row["source"]?.textValue ?? "user") ?? .user
        )
    }

    private static func encodeUUIDs(_ uuids: [UUID]) -> String {
        let strings = uuids.map { "\"\($0.uuidString)\"" }
        return "[\(strings.joined(separator: ","))]"
    }

    private static func decodeUUIDs(_ json: String) -> [UUID] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return array.compactMap { UUID(uuidString: $0) }
    }

    private static func encodeParams(_ params: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(params),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private static func decodeParams(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }
}
