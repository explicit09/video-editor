import SwiftUI
import AVFoundation
import EditorCore

struct PreviewPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Video view
            AVPlayerView(player: appState.playbackEngine.player)
                .background(.black)

            Divider()

            // Transport controls
            transportBar
        }
        .background(.black)
    }

    // MARK: - Transport bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            // Timecode
            Text(formatTimecode(appState.playbackEngine.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 80, alignment: .leading)

            Spacer()

            // Transport buttons
            Button(action: { appState.playbackEngine.seek(to: 0) }) {
                Image(systemName: "backward.end.fill")
            }

            Button(action: { appState.playbackEngine.togglePlayPause() }) {
                Image(systemName: appState.playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }

            Button(action: {
                appState.playbackEngine.seek(to: appState.playbackEngine.duration)
            }) {
                Image(systemName: "forward.end.fill")
            }

            Spacer()

            // Duration
            Text(formatTimecode(appState.playbackEngine.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 80, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
    }

    private func formatTimecode(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let frames = Int((t - Double(Int(t))) * 30)
        return String(format: "%02d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - AVPlayerView (NSViewRepresentable)

struct AVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerNSView {
        let view = AVPlayerNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerNSView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

/// Minimal NSView that hosts an AVPlayerLayer.
final class AVPlayerNSView: NSView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    private let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
