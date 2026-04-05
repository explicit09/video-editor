import SwiftUI
import EditorCore

struct TrackHeaderColumnView: View {
    let tracks: [Track]
    let viewState: TimelineViewState
    let coordinator: TimelineScrollCoordinator
    let rowHeight: Double

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: CinematicSpacing.clipGap) {
                ForEach(tracks) { track in
                    TrackHeaderRowView(track: track, viewState: viewState, rowHeight: rowHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .offset(y: -coordinator.verticalOffset)
        }
        .clipped()
        .background(CinematicTheme.surfaceContainer)
    }
}

private struct TrackHeaderRowView: View {
    let track: Track
    let viewState: TimelineViewState
    let rowHeight: Double

    private var accent: Color {
        switch track.type {
        case .video: CinematicTheme.primary
        case .audio: CinematicTheme.success
        case .text: CinematicTheme.tertiary
        case .effect: CinematicTheme.aqua
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(CinematicTheme.onSurface.opacity(0.18), lineWidth: 0.5))

                Text(track.type.rawValue.uppercased())
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))

                Spacer(minLength: 0)

                Text("\(track.clips.count)")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.74))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(Capsule())
            }

            Text(track.name)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if track.isMuted {
                    headerBadge(icon: "speaker.slash", label: "Muted", tone: CinematicTheme.warning)
                }
                if track.isLocked {
                    headerBadge(icon: "lock.fill", label: "Locked", tone: CinematicTheme.onSurfaceVariant)
                }
                if viewState.selectedTrackID == track.id {
                    headerBadge(icon: "checkmark.circle.fill", label: "Selected", tone: CinematicTheme.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: rowHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .fill(CinematicTheme.surfaceContainerHighest.opacity(0.72))
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.24))
                .frame(width: 1)
        }
    }

    private func headerBadge(icon: String, label: String, tone: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(tone)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(tone.opacity(0.12))
        .clipShape(Capsule())
    }
}
