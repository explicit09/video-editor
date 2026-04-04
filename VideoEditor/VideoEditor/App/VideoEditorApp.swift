import SwiftUI
import AppKit
import Combine

@main
struct VideoEditorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        appState.flushPendingState()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.shutdown()
                }
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
