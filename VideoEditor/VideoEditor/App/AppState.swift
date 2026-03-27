import SwiftUI
import EditorCore

@Observable
@MainActor
final class AppState {
    let context: EditingContext
    let commandHistory: CommandHistory
    let intentResolver: IntentResolver
    let timelineViewState: TimelineViewState

    // Reactive access — SwiftUI reads these directly
    var timeline: Timeline { context.timelineState.timeline }
    private(set) var assets: [MediaAsset] = []

    init() {
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
        self.timelineViewState = TimelineViewState()
    }

    // MARK: - The ONLY write path for editing actions

    /// Execute an intent through the full pipeline: Intent → Command → Execute
    /// This is the single entry point for ALL timeline mutations.
    func perform(_ intent: EditorIntent) throws {
        var command = try intentResolver.resolve(intent)
        try commandHistory.execute(&command, context: context)
    }

    func undo() throws {
        try commandHistory.undo(context: context)
    }

    func redo() throws {
        try commandHistory.redo(context: context)
    }

    // MARK: - Media import (not a timeline mutation, so not routed through intents)

    func importMedia(from url: URL, bundleMediaDir: URL?) async throws -> MediaAsset {
        let asset = try await context.media.importFile(from: url, bundleMediaDir: bundleMediaDir)
        assets = await context.media.allAssets()
        return asset
    }

    func refreshAssets() async {
        assets = await context.media.allAssets()
    }
}
