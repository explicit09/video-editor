import SwiftUI
import AppKit
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

    private var isEditable: Bool {
        !track.isLocked
    }

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
                .opacity(track.isLocked ? 0.94 : 1)
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
                .overlay(alignment: .topTrailing) {
                    if track.isLocked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.8))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(CinematicTheme.surfaceContainerHighest.opacity(0.9))
                            .clipShape(Capsule())
                            .padding(8)
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
                    isEditable: isEditable,
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
            guard isEditable else { return false }
            guard let item = items.first else { return false }
            dropX = location.x
            onAssetDrop(item.assetID, viewState.xToTime(location.x))
            return true
        }, isTargeted: { targeted in
            isDropTargeted = targeted && isEditable
            if !targeted || !isEditable {
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
                trackAccentColor.opacity(track.isLocked ? 0.03 : (isSelectedTrack ? 0.14 : 0.05)),
                CinematicTheme.surfaceContainerLowest,
                trackAccentColor.opacity(isDropTargeted ? 0.16 : (track.isLocked ? 0.02 : 0.03)),
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

private struct TimelineClipView: View {
    let clip: Clip
    let viewState: TimelineViewState
    let isSelected: Bool
    let trackType: TrackType
    let trackHeight: Double
    let isEditable: Bool
    let thumbnail: CGImage?
    let waveform: [Float]?
    let onTap: (Bool) -> Void
    let onDrag: (TimeInterval, Double) -> Void
    var onTrimStart: ((TimeInterval) -> Void)?
    var onTrimEnd: ((TimeInterval) -> Void)?
    var onSplit: ((TimeInterval) -> Void)?
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?

    @State private var dragOffset: Double = 0
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var trimStartOffset: Double = 0
    @State private var trimEndOffset: Double = 0
    @State private var isTrimming = false

    private var clipX: Double {
        viewState.durationToWidth(clip.timelineRange.start) + dragOffset + trimStartOffset
    }

    private var clipWidth: Double {
        max(viewState.durationToWidth(clip.timelineRange.duration) - trimStartOffset + trimEndOffset, 8)
    }

    var body: some View {
        clipBody
            .frame(width: clipWidth, height: trackHeight - 8)
            .position(x: clipX + clipWidth / 2, y: trackHeight / 2)
            .gesture(dragGesture)
            .simultaneousGesture(tapGesture)
            .contextMenu {
                Button("Split at Playhead") { onSplit?(clip.timelineRange.start + clip.timelineRange.duration / 2) }
                    .disabled(!isEditable)
                Button("Duplicate") { onDuplicate?() }
                    .disabled(!isEditable)
                Divider()
                Button("Delete", role: .destructive) { onDelete?() }
                    .disabled(!isEditable)
            }
    }

    private var clipBody: some View {
        Group {
            if trackType == .audio {
                audioClipBody
            } else {
                visualClipBody
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(outlineColor, lineWidth: outlineWidth)
        )
        .shadow(color: shadowColor, radius: isDragging ? 12 : 8, y: isDragging ? 6 : 2)
        .overlay(alignment: .topTrailing) {
            if !isEditable {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CinematicTheme.onSurface.opacity(0.86))
                    .padding(6)
                    .background(CinematicTheme.surfaceContainerHighest.opacity(0.9))
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .overlay(alignment: .leading) {
            if isEditable {
                trimHandle(isStart: true)
            }
        }
        .overlay(alignment: .trailing) {
            if isEditable {
                trimHandle(isStart: false)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var visualClipBody: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(clipAccentColor)
                .frame(height: 3)

            ZStack {
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .fill(clipBackground)

                if let cgImage = thumbnail, trackType == .video {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.05),
                                    Color.black.opacity(0.38),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .opacity(0.72)
                } else {
                    Rectangle()
                        .fill(clipBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(clipLabel, alignment: .topLeading)
            .overlay(alignment: .bottomLeading) {
                clipFooter
            }
        }
    }

    private var audioClipBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .fill(audioClipBackground)

            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .fill(Color.black.opacity(0.08))
                .padding(.horizontal, 4)
                .padding(.vertical, 5)

            if let waveform, !waveform.isEmpty {
                WaveformView(amplitudes: waveform, color: audioWaveformColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            } else {
                Capsule()
                    .fill(audioWaveformColor.opacity(0.26))
                    .frame(height: 2)
                    .padding(.horizontal, 14)
            }
        }
        .overlay(clipLabel, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            clipFooter
        }
    }

    private func trimHandle(isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: CinematicRadius.full)
            .fill(isSelected || isTrimming || isHovered ? CinematicTheme.onSurface.opacity(0.85) : Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                guard isEditable else { return }
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard isEditable else { return }
                        isTrimming = true
                        if isStart {
                            trimStartOffset = value.translation.width
                        } else {
                            trimEndOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard isEditable else {
                            trimStartOffset = 0
                            trimEndOffset = 0
                            isTrimming = false
                            return
                        }

                        isTrimming = false
                        let timeDelta = value.translation.width / viewState.zoom
                        if isStart {
                            trimStartOffset = 0
                            let newStart = max(0, clip.sourceRange.start + timeDelta)
                            onTrimStart?(newStart)
                        } else {
                            trimEndOffset = 0
                            let newEnd = max(clip.sourceRange.start + 0.1, clip.sourceRange.end + timeDelta)
                            onTrimEnd?(newEnd)
                        }
                    }
            )
    }

    private var clipLabel: some View {
        Text(clip.metadata.label ?? "Clip")
            .font(.cinLabelRegular)
            .foregroundStyle(CinematicTheme.onSurface)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(trackType == .audio ? 0.24 : 0.42))
            .clipShape(Capsule())
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    private var clipFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: footerIcon)
                .font(.system(size: 9, weight: .bold))
            Text(TimeFormatter.duration(max(clip.timelineRange.duration, 0.1)))
                .font(.cinLabelRegular)
                .monospacedDigit()
        }
        .foregroundStyle(CinematicTheme.onSurface.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var footerIcon: String {
        switch trackType {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        case .effect: "sparkles"
        }
    }

    private var clipBackground: LinearGradient {
        let leading = clipAccentColor.opacity(trackType == .audio ? 0.22 : 0.18)
        let trailing = CinematicTheme.surfaceContainerLowest

        return LinearGradient(
            colors: [
                leading,
                trailing,
                clipAccentColor.opacity(isSelected ? 0.12 : 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var audioClipBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0x1B4625),
                Color(hex: 0x1F5D2D),
                Color(hex: 0x173D23),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var audioWaveformColor: Color {
        Color(hex: 0xB8FFC5)
    }

    private var clipAccentColor: Color {
        switch trackType {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
    }

    private var outlineColor: Color {
        if isSelected {
            return CinematicTheme.primary
        }
        if isHovered || isDragging {
            return clipAccentColor.opacity(0.85)
        }
        return CinematicTheme.outlineVariant.opacity(0.24)
    }

    private var outlineWidth: Double {
        isSelected ? 1.6 : (isHovered ? 1.0 : 0.6)
    }

    private var shadowColor: Color {
        if isSelected || isDragging {
            return clipAccentColor.opacity(0.24)
        }
        return .clear
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                onTap(NSEvent.modifierFlags.contains(.shift))
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard isEditable else { return }
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard isEditable else {
                    dragOffset = 0
                    isDragging = false
                    return
                }

                isDragging = false
                let timeDelta = value.translation.width / viewState.zoom
                let newStart = max(0, clip.timelineRange.start + timeDelta)
                dragOffset = 0
                onDrag(newStart, value.translation.height)
            }
    }
}
