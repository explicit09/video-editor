import SwiftUI
import AVFoundation

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
                    .background(UtilityTheme.recessed)
            } else {
                Rectangle()
                    .fill(UtilityTheme.recessed)
            }

            if let emptyState {
                MonitorEmptyStateOverlay(state: emptyState)
            }

            overlayContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct MonitorEmptyStateOverlay: View {
    let state: MonitorEmptyState

    var body: some View {
        VStack(spacing: UtilitySpacing.md) {
            Image(systemName: state.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(UtilityTheme.accent)
                .frame(width: 52, height: 52)
                .background(UtilityTheme.chromeElevated)
                .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.lg))

            VStack(spacing: UtilitySpacing.xxs) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UtilityTheme.text)
                Text(state.detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(UtilityTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(UtilitySpacing.lg)
        .background(UtilityTheme.recessed.opacity(0.12))
    }
}
