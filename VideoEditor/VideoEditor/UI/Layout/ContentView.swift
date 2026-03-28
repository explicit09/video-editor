import SwiftUI
import EditorCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedWorkspace: Workspace = .edit
    @State private var commandBarText = ""
    @State private var showSettings = false

    enum Workspace: String, CaseIterable {
        case edit = "Edit"
        case transcript = "Script"
        case media = "Media"
        case ai = "AI"
        case deliver = "Deliver"

        var icon: String {
            switch self {
            case .edit: "film"
            case .transcript: "text.alignleft"
            case .media: "photo.on.rectangle"
            case .ai: "sparkles"
            case .deliver: "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                sideNav
                if appState.assets.isEmpty && appState.timeline.tracks.isEmpty {
                    EmptyStateView(commandBarText: $commandBarText, onSend: sendCommandBarMessage)
                } else if selectedWorkspace == .media {
                    MediaWorkspacePanel()
                } else if selectedWorkspace == .deliver {
                    deliverWorkspace
                } else {
                    mainContent
                }
            }
        }
        .background(CinematicTheme.surface)
        .frame(minWidth: 1200, minHeight: 700)
        .focusable()
        // Transport: J/K/L
        .onKeyPress("j") { stepBackward(); return .handled }
        .onKeyPress("k") { appState.playbackEngine.togglePlayPause(); return .handled }
        .onKeyPress("l") { stepForward(); return .handled }
        // Frame stepping: arrows
        .onKeyPress(.leftArrow) { stepFrame(forward: false); return .handled }
        .onKeyPress(.rightArrow) { stepFrame(forward: true); return .handled }
        // Zoom: +/-
        .onKeyPress("=") { appState.timelineViewState.zoomIn(); return .handled }
        .onKeyPress("-") { appState.timelineViewState.zoomOut(); return .handled }
    }

    // MARK: - Keyboard actions

    private func stepForward() {
        let newTime = min(appState.playbackEngine.currentTime + 5, appState.playbackEngine.duration)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    private func stepBackward() {
        let newTime = max(appState.playbackEngine.currentTime - 5, 0)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    private func stepFrame(forward: Bool) {
        let frameDuration = 1.0 / 30.0
        let newTime = forward
            ? min(appState.playbackEngine.currentTime + frameDuration, appState.playbackEngine.duration)
            : max(appState.playbackEngine.currentTime - frameDuration, 0)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            // App title
            Text("The Cinematic Canvas")
                .font(.cinTitleSmall)
                .fontWeight(.bold)
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.leading, 78) // past sidebar width

            Spacer()

            // AI status badge
            if appState.aiChat.isProcessing {
                Text("AI ACTIVE")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.primaryContainer)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CinematicTheme.primaryContainer.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            }

            // Export (always accessible)
            ExportButton()
                .padding(.trailing, 8)

            // Settings
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .foregroundStyle(CinematicTheme.primary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .sheet(isPresented: $showSettings) {
                SettingsSheet(isPresented: $showSettings)
            }
        }
        .frame(height: 40)
        .background(CinematicTheme.surface)
    }

    // MARK: - Side Navigation

    private var sideNav: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                ForEach(Workspace.allCases, id: \.self) { workspace in
                    sideNavItem(workspace)
                }
            }
            .padding(.top, 24)

            Spacer()

            // AI bolt button — switch to AI workspace
            Button(action: { selectedWorkspace = .ai }) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .frame(width: 36, height: 36)
                    .background(CinematicTheme.primaryContainer)
                    .clipShape(Circle())
                    .aiGlow()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(width: 64)
        .background(CinematicTheme.surfaceContainerLow)
    }

    private func sideNavItem(_ workspace: Workspace) -> some View {
        let isSelected = selectedWorkspace == workspace
        return Button(action: { selectedWorkspace = workspace }) {
            VStack(spacing: 4) {
                Image(systemName: workspace.icon)
                    .font(.system(size: 20))
                Text(workspace.rawValue)
                    .font(.cinLabel)
                    .tracking(1)
                    .textCase(.uppercase)
            }
            .foregroundStyle(isSelected ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.6))
            .frame(width: 64, height: 56)
            .background(
                isSelected
                    ? LinearGradient(colors: [CinematicTheme.primaryContainer.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)
            )
            .overlay(alignment: .trailing) {
                if isSelected {
                    Rectangle()
                        .fill(CinematicTheme.primaryContainer)
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top workspace: Media Browser + Preview + Inspector
            HStack(spacing: 0) {
                // Left panel — switches based on workspace
                leftPanel
                    .frame(width: 260)

                // Preview with floating AI command bar above transport
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        AVPlayerView(player: appState.playbackEngine.player)
                            .background(CinematicTheme.surfaceContainerLowest)

                        // AI Orchestrator overlay (Screen 3)
                        if appState.aiChat.isProcessing {
                            aiOrchestratorOverlay
                        }

                        // Floating AI Command Bar
                        aiCommandBar
                            .padding(.bottom, 16)
                            .padding(.horizontal, 40)
                    }

                    // Transport controls below preview
                    transportBar
                }

                InspectorPanel()
                    .frame(width: 280)
            }
            .frame(minHeight: 300)

            // Timeline
            TimelinePanel()
                .frame(minHeight: 150, idealHeight: 250)
        }
    }

    // MARK: - Left Panel (workspace-dependent)

    @ViewBuilder
    private var leftPanel: some View {
        switch selectedWorkspace {
        case .transcript:
            TranscriptPanel()
        default:
            MediaBrowserPanel()
        }
    }

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            Text(TimeFormatter.timecode(appState.playbackEngine.currentTime))
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurface.opacity(0.7))
                .frame(width: 100, alignment: .leading)

            Spacer()

            HStack(spacing: 20) {
                Button(action: { appState.playbackEngine.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                }

                Button(action: { appState.playbackEngine.togglePlayPause() }) {
                    Image(systemName: appState.playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(CinematicTheme.primaryContainer)
                        .clipShape(Circle())
                        .foregroundStyle(CinematicTheme.onPrimaryContainer)
                }

                Button(action: {
                    appState.playbackEngine.seek(to: appState.playbackEngine.duration)
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                }
            }
            .foregroundStyle(CinematicTheme.onSurface.opacity(0.8))
            .buttonStyle(.plain)

            Spacer()

            Text(TimeFormatter.timecode(appState.playbackEngine.duration))
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(CinematicTheme.surface)
    }


    // MARK: - Floating AI Command Bar

    // MARK: - Deliver Workspace

    @State private var showExportDialog = false

    private var deliverWorkspace: some View {
        VStack {
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(CinematicTheme.primary.opacity(0.4))
            Text("Ready to deliver")
                .font(.cinHeadline)
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.top, 12)
            Text("\(appState.timeline.tracks.count) tracks • \(appState.timeline.tracks.flatMap(\.clips).count) clips")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
                .padding(.top, 4)

            Button(action: { showExportDialog = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                    Text("Export Project")
                        .font(.cinTitle)
                }
                .foregroundStyle(CinematicTheme.onPrimaryContainer)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(CinematicTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .disabled(appState.timeline.tracks.isEmpty)
            .sheet(isPresented: $showExportDialog) {
                ExportDialog(isPresented: $showExportDialog)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CinematicTheme.surface)
    }

    // MARK: - AI Orchestrator Overlay (Screen 3)

    private var aiOrchestratorOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(CinematicTheme.primary)
                    .symbolEffect(.pulse)

                Text("AI Orchestrator Active")
                    .font(.cinTitleSmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(CinematicTheme.onSurface)
            }

            if let status = appState.aiChat.processingStatus {
                Text(status)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassPanel()
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.full)
                .strokeBorder(CinematicTheme.primaryContainer.opacity(0.3), lineWidth: 1)
        )
        .aiGlow(radius: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 80) // Above the command bar
    }

    private func sendCommandBarMessage() {
        let text = commandBarText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        commandBarText = ""
        Task {
            await appState.aiChat.send(message: text, appState: appState)
        }
    }

    private var aiCommandBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(appState.aiChat.isProcessing ? CinematicTheme.primary : CinematicTheme.primary.opacity(0.6))
                .font(.system(size: 14))
                .symbolEffect(.pulse, isActive: appState.aiChat.isProcessing)

            TextField("Ask AI to edit, color grade, or find clips...", text: $commandBarText)
                .textFieldStyle(.plain)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .onSubmit { sendCommandBarMessage() }
                .disabled(appState.aiChat.isProcessing)

            if appState.aiChat.isProcessing {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(CinematicTheme.primary)
            } else {
                Button(action: sendCommandBarMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            commandBarText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? CinematicTheme.onSurfaceVariant.opacity(0.3)
                                : CinematicTheme.primaryContainer
                        )
                }
                .buttonStyle(.plain)
                .disabled(commandBarText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassPanel()
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.full)
                .strokeBorder(CinematicTheme.outlineVariant.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Settings sheet for configuring API keys.
private struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var anthropicKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.cinHeadline)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 16) {
                Text("API KEYS")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))

                apiKeyField(
                    label: "Anthropic API Key",
                    placeholder: "sk-ant-...",
                    value: $anthropicKey,
                    description: "Powers the AI assistant. Get one at console.anthropic.com"
                )

                apiKeyField(
                    label: "Deepgram API Key",
                    placeholder: "Enter key...",
                    value: $deepgramKey,
                    description: "Powers transcription. Get one at deepgram.com"
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack {
                if saved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: 0x53E16F))
                        Text("Saved - restart app to apply")
                            .font(.cinLabelRegular)
                            .foregroundStyle(Color(hex: 0x53E16F))
                    }
                }
                Spacer()
                Button(action: saveKeys) {
                    Text("Save")
                        .font(.cinTitleSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(CinematicTheme.onPrimaryContainer)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(CinematicTheme.primaryContainer)
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 480, height: 360)
        .background(CinematicTheme.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.xl))
        .onAppear { loadKeys() }
    }

    private func apiKeyField(label: String, placeholder: String, value: Binding<String>, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.cinTitleSmall)
                .foregroundStyle(CinematicTheme.onSurface)
            SecureField(placeholder, text: value)
                .textFieldStyle(.plain)
                .font(.cinBody)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CinematicTheme.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            Text(description)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
        }
    }

    private func loadKeys() {
        let envURL = envFileURL()
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let val = String(trimmed[trimmed.index(after: eq)...])
            if key == "ANTHROPIC_API_KEY" { anthropicKey = val }
            if key == "DEEPGRAM_API_KEY" { deepgramKey = val }
        }
    }

    private func saveKeys() {
        var lines: [String] = []
        if !anthropicKey.isEmpty { lines.append("ANTHROPIC_API_KEY=\(anthropicKey)") }
        if !deepgramKey.isEmpty { lines.append("DEEPGRAM_API_KEY=\(deepgramKey)") }
        let content = lines.joined(separator: "\n") + "\n"

        let url = envFileURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        saved = true
    }

    private func envFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VideoEditor/.env")
    }
}
