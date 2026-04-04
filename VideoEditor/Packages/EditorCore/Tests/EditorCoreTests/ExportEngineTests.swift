import Testing
import Foundation
@testable import EditorCore

@Suite("Export Engine Tests")
struct ExportEngineTests {

    @MainActor
    @Test("Export fails cleanly when the timeline is empty")
    func exportRejectsEmptyTimeline() async {
        let engine = ExportEngine()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("empty-export.mp4")

        await engine.export(timeline: Timeline(), assets: [], to: outputURL)

        #expect(engine.state == .failed("Nothing to export"))
    }
}
