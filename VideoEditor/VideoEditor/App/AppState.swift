import SwiftUI
import EditorCore

@Observable
@MainActor
final class AppState {
    let context: EditingContext
    let commandHistory: CommandHistory
    let intentResolver: IntentResolver

    init() {
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
    }

    /// Execute an intent through the full pipeline: Intent → Command → Execute
    func perform(_ intent: EditorIntent) throws {
        var command = try intentResolver.resolve(intent, context: context)
        try commandHistory.execute(&command, context: context)
    }
}
