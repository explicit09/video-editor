import SwiftUI
import AVFoundation
import AppKit

struct MonitorEmptyState: Equatable, Sendable {
    let icon: String
    let title: String
    let detail: String
}

struct MonitorViewport<OverlayContent: View>: View {
    let player: AVPlayer?
    let emptyState: MonitorEmptyState?
    @ViewBuilder var overlayContent: OverlayContent

    init(
        player: AVPlayer?,
        emptyState: MonitorEmptyState? = nil,
        @ViewBuilder overlayContent: () -> OverlayContent = { EmptyView() }
    ) {
        self.player = player
        self.emptyState = emptyState
        self.overlayContent = overlayContent()
    }

    var body: some View {
        ZStack {
            if let player {
                AVPlayerView(player: player)
                    .background(CinematicTheme.surfaceContainerLowest)
            } else {
                Rectangle()
                    .fill(CinematicTheme.surfaceContainerLowest)
            }

            if let emptyState {
                CinematicEmptyStateBlock(
                    icon: emptyState.icon,
                    title: emptyState.title,
                    detail: emptyState.detail
                )
            }

            overlayContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

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
