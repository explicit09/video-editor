import SwiftUI
import AVFoundation
import EditorCore

struct PreviewPanel: View {
    let player: AVPlayer
    let layoutMode: EditorLayoutMode
    let isProcessing: Bool
    let processingStatus: String?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let clipCount: Int

    var body: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "PREVIEW",
                title: "Program Monitor",
                subtitle: layoutMode == .compact ? "Compact edit view" : "Unified edit view",
                trailingAccessory: {
                    HStack(spacing: 8) {
                        CinematicStatusPill(
                            text: TimeFormatter.timecode(currentTime),
                            icon: "playhead",
                            tone: CinematicTheme.aqua
                        )
                        CinematicStatusPill(
                            text: "\(clipCount) clips",
                            icon: "rectangle.stack",
                            tone: CinematicTheme.tertiary
                        )
                    }
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

            ZStack {
                AVPlayerView(player: player)
                    .background(CinematicTheme.surfaceContainerLowest)

                if duration == 0 {
                    CinematicEmptyStateBlock(
                        icon: "rectangle.on.rectangle.angled",
                        title: "No active composition",
                        detail: "Import media or add clips to the timeline to populate the preview."
                    )
                }

                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(CinematicTheme.primary)
                        Text(processingStatus ?? "AI is analyzing the edit…")
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassPanel(tint: CinematicTheme.surfaceGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: CinematicRadius.lg)
                            .strokeBorder(CinematicTheme.primary.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.bottom, 28)
                }
            }
            .frame(minHeight: layoutMode == .compact ? 300 : 360)
        }
        .panelSurface(.elevated, strokeOpacity: 0.9)
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
