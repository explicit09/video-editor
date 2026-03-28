import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import EditorCore

struct TimelineTrackView: View {
    let track: Track
    let trackHeight: Double
    let viewState: TimelineViewState
    let selectedClipIDs: Set<UUID>
    let isSelectedTrack: Bool
    let totalWidth: Double
    let thumbnails: [UUID: CGImage]
    let waveforms: [UUID: [Float]]
    let onTrackTap: () -> Void
    let onRenameTrack: (String) -> Void
    let onToggleMute: () -> Void
    let onToggleLock: () -> Void
    let onAddLane: () -> Void
    let onCycleHeight: () -> Void
    let onRemoveTrack: (() -> Void)?
    let onClipTap: (UUID, Bool) -> Void
    let onClipDrag: (UUID, TimeInterval, Double) -> Void
    let onAssetDrop: (UUID, TimeInterval) -> Void
    var onClipTrim: ((UUID, TimeInterval, TimeInterval) -> Void)?
    var onClipSplit: ((UUID, TimeInterval) -> Void)?
    var onClipDelete: ((UUID) -> Void)?
    var onClipDuplicate: ((UUID) -> Void)?

    @State private var isDropTargeted = false
    @State private var dropX: Double?
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 0) {
            trackLabel
            clipArea
        }
        .frame(height: trackHeight)
        .clipped()
        .onAppear { draftName = resolvedTrackName }
        .onChange(of: track.name) { _, newValue in
            if draftName != newValue {
                draftName = newValue
            }
        }
    }

    private var clipArea: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(trackBackgroundGradient)
                .frame(width: totalWidth, height: trackHeight)
                .overlay(alignment: .topLeading) {
                    if isSelectedTrack {
                        RoundedRectangle(cornerRadius: CinematicRadius.lg)
                            .strokeBorder(trackAccentColor.opacity(0.34), lineWidth: 1.2)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                    }
                }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: CinematicRadius.lg)
                            .stroke(trackAccentColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .padding(2)
                    }
                }
                .overlay(alignment: .leading) {
                    if let dropX, isDropTargeted {
                        Rectangle()
                            .fill(trackAccentColor)
                            .frame(width: 2, height: max(trackHeight - 14, 0))
                            .offset(x: max(dropX - 1, 0), y: 0)
                            .padding(.vertical, 7)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewState.clearSelection()
                    onTrackTap()
                }

            ForEach(track.clips) { clip in
                TimelineClipView(
                    clip: clip,
                    viewState: viewState,
                    isSelected: selectedClipIDs.contains(clip.id),
                    trackType: track.type,
                    trackHeight: trackHeight,
                    thumbnail: thumbnails[clip.assetID],
                    waveform: waveforms[clip.assetID],
                    onTap: { extend in onClipTap(clip.id, extend) },
                    onDrag: { newStart, verticalOffset in onClipDrag(clip.id, newStart, verticalOffset) },
                    onTrimStart: { newSourceStart in
                        onClipTrim?(clip.id, newSourceStart, clip.sourceRange.end)
                    },
                    onTrimEnd: { newSourceEnd in
                        onClipTrim?(clip.id, clip.sourceRange.start, newSourceEnd)
                    },
                    onSplit: { at in onClipSplit?(clip.id, at) },
                    onDelete: { onClipDelete?(clip.id) },
                    onDuplicate: { onClipDuplicate?(clip.id) }
                )
            }
        }
        .dropDestination(for: TimelineAssetDragPayload.self, action: { items, location in
            guard let item = items.first else { return false }
            dropX = location.x
            onAssetDrop(item.assetID, viewState.xToTime(location.x))
            return true
        }, isTargeted: { targeted in
            isDropTargeted = targeted
            if !targeted {
                dropX = nil
            }
        })
    }

    private var trackLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: trackIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(trackAccentColor)

                Text(track.type.rawValue.uppercased())
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))

                Spacer(minLength: 0)

                Text("\(track.clips.count)")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(Capsule())
            }

            TextField("Track Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.cinTitleSmall)
                .foregroundStyle(CinematicTheme.onSurface)
                .onSubmit(commitTrackName)

            HStack(spacing: 6) {
                trackControlButton(
                    icon: muteIcon,
                    isActive: !track.isMuted,
                    tooltip: track.isMuted ? "Unmute track" : "Mute track",
                    action: onToggleMute
                )

                trackControlButton(
                    icon: track.isLocked ? "lock.fill" : "lock.open.fill",
                    isActive: track.isLocked,
                    tooltip: track.isLocked ? "Unlock track" : "Lock track",
                    action: onToggleLock
                )

                trackControlButton(
                    icon: "plus",
                    isActive: false,
                    tooltip: "Add \(track.type.rawValue) lane",
                    action: onAddLane
                )

                trackControlButton(
                    icon: "arrow.up.and.down.text.horizontal",
                    isActive: false,
                    tooltip: "Cycle lane height",
                    action: onCycleHeight
                )

                if let onRemoveTrack {
                    trackControlButton(
                        icon: "trash",
                        isActive: false,
                        isDestructive: true,
                        tooltip: "Remove empty track",
                        action: onRemoveTrack
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 182, height: trackHeight, alignment: .leading)
        .background(trackHeaderBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.24))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTrackTap() }
    }

    private func commitTrackName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextName = trimmed.isEmpty ? defaultTrackName : trimmed
        draftName = nextName
        onRenameTrack(nextName)
    }

    private func trackControlButton(
        icon: String,
        isActive: Bool,
        isDestructive: Bool = false,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(buttonForeground(isActive: isActive, isDestructive: isDestructive))
                .frame(width: 24, height: 24)
                .background(buttonBackground(isActive: isActive, isDestructive: isDestructive))
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func buttonBackground(isActive: Bool, isDestructive: Bool) -> Color {
        if isDestructive {
            return CinematicTheme.errorContainer.opacity(0.28)
        }
        return isActive ? trackAccentColor.opacity(0.22) : CinematicTheme.surfaceContainerHighest
    }

    private func buttonForeground(isActive: Bool, isDestructive: Bool) -> Color {
        if isDestructive {
            return CinematicTheme.error
        }
        return isActive ? trackAccentColor : CinematicTheme.onSurfaceVariant.opacity(0.72)
    }

    private var defaultTrackName: String {
        "\(track.type.rawValue.capitalized) \(track.clips.isEmpty ? "Lane" : "Track")"
    }

    private var resolvedTrackName: String {
        track.name.isEmpty ? defaultTrackName : track.name
    }

    private var muteIcon: String {
        switch track.type {
        case .audio:
            track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        default:
            track.isMuted ? "eye.slash.fill" : "eye.fill"
        }
    }

    private var trackHeaderBackground: LinearGradient {
        LinearGradient(
            colors: [
                CinematicTheme.surfaceContainerLow,
                trackAccentColor.opacity(isSelectedTrack ? 0.14 : 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var trackBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                trackAccentColor.opacity(isSelectedTrack ? 0.14 : 0.05),
                CinematicTheme.surfaceContainerLowest,
                trackAccentColor.opacity(isDropTargeted ? 0.16 : 0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var trackIcon: String {
        switch track.type {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        case .effect: "sparkles"
        }
    }

    private var trackAccentColor: Color {
        switch track.type {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
    }
}
