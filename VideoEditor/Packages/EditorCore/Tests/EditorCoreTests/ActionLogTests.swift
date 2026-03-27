import Testing
import Foundation
@testable import EditorCore

@Suite("ActionLog SQLite Tests")
struct ActionLogTests {

    @Test("Records and queries events from SQLite")
    func recordAndQuery() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).sqlite").path

        let log = ActionLog()
        try await log.open(at: tempDB)

        let clipID = UUID()
        let trackID = UUID()

        await log.record(
            commandName: "Insert Clip",
            clipIDs: [clipID],
            trackIDs: [trackID],
            parameters: ["position": "5.0"],
            source: .user
        )
        await log.record(
            commandName: "Move Clip",
            clipIDs: [clipID],
            parameters: ["newStart": "10.0"],
            source: .user
        )

        let all = await log.allEvents()
        #expect(all.count == 2)
        #expect(all[0].commandName == "Insert Clip")
        #expect(all[0].clipIDs == [clipID])
        #expect(all[0].trackIDs == [trackID])
        #expect(all[0].parameters["position"] == "5.0")
        #expect(all[0].source == .user)

        #expect(all[1].commandName == "Move Clip")

        // Query by clip
        let clipEvents = await log.actionsFor(clip: clipID)
        #expect(clipEvents.count == 2)

        // Query recent
        let recent = await log.recentActions(count: 1)
        #expect(recent.count == 1)
        #expect(recent[0].commandName == "Move Clip")

        // Event count
        let count = await log.eventCount()
        #expect(count == 2)

        try? FileManager.default.removeItem(atPath: tempDB)
    }

    @Test("Falls back to in-memory before database is opened")
    func inMemoryFallback() async {
        let log = ActionLog()

        // Record before opening DB
        await log.record(commandName: "Add Track", source: .user)
        let events = await log.allEvents()
        #expect(events.count == 1)
        #expect(events[0].commandName == "Add Track")
    }

    @Test("Flushes in-memory events when database opens")
    func flushOnOpen() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).sqlite").path

        let log = ActionLog()

        // Record before DB
        await log.record(commandName: "Pre-open Event", source: .user)

        // Open DB — should flush
        try await log.open(at: tempDB)

        // Record after DB
        await log.record(commandName: "Post-open Event", source: .ai)

        let all = await log.allEvents()
        #expect(all.count == 2)
        #expect(all[0].commandName == "Pre-open Event")
        #expect(all[1].commandName == "Post-open Event")

        try? FileManager.default.removeItem(atPath: tempDB)
    }
}
