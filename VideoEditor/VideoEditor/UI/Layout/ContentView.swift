import SwiftUI
import EditorCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedWorkspace: Workspace = .edit

    enum Workspace: String, CaseIterable {
        case edit = "Edit"
        case color = "Color"
        case audio = "Audio"
        case deliver = "Deliver"

        var icon: String {
            switch self {
            case .edit: "film"
            case .color: "paintpalette"
            case .audio: "waveform"
            case .deliver: "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                sideNav
                mainContent
            }
        }
        .background(CinematicTheme.surface)
        .frame(minWidth: 1200, minHeight: 700)
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

            // Settings
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .foregroundStyle(CinematicTheme.primary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
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

            // AI bolt button
            Button(action: {}) {
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
                MediaBrowserPanel()
                    .frame(width: 260)

                // Preview with floating AI command bar above transport
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        AVPlayerView(player: appState.playbackEngine.player)
                            .background(CinematicTheme.surfaceContainerLowest)

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

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            Text(formatTimecode(appState.playbackEngine.currentTime))
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

            Text(formatTimecode(appState.playbackEngine.duration))
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(CinematicTheme.surface)
    }

    private func formatTimecode(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let hrs = Int(t) / 3600
        let mins = (Int(t) % 3600) / 60
        let secs = Int(t) % 60
        let frames = Int((t - Double(Int(t))) * 30)
        return String(format: "%02d:%02d:%02d:%02d", hrs, mins, secs, frames)
    }

    // MARK: - Floating AI Command Bar

    private var aiCommandBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(CinematicTheme.primary)
                .font(.system(size: 14))

            TextField("Ask AI to edit, color grade, or find clips...", text: .constant(""))
                .textFieldStyle(.plain)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant)

            Button(action: {}) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(CinematicTheme.primaryContainer)
            }
            .buttonStyle(.plain)
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
