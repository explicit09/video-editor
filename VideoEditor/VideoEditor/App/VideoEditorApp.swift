import SwiftUI

@main
struct VideoEditorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { try? appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.commandHistory.canUndo)

                Button("Redo") { try? appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.commandHistory.canRedo)
            }
        }
    }
}
