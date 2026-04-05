import SwiftUI
import EditorCore

struct TrackHeaderRowView: View {
    @Environment(AppState.self) private var appState

    let track: Track
    let viewState: TimelineViewState
    let layoutState: TrackLayoutState

    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isCollapsed: Bool {
        layoutState.isCollapsed(track.id)
    }

    private var rowHeight: Double {
        layoutState.height(for: track)
    }

    private var headerLayout: TrackHeaderLayout {
        TrackHeaderLayout.make(
            isCollapsed: isCollapsed,
            canRemoveTrack: removableAction != nil
        )
    }

    private var trackAccentColor: Color {
        switch track.type {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
    }

    private var trackIcon: String {
        switch track.type {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        case .effect: "sparkles"
        }
    }

    private var muteIcon: String {
        switch track.type {
        case .audio:
            track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        default:
            track.isMuted ? "eye.slash.fill" : "eye.fill"
        }
    }

    private var soloIcon: String {
        track.isSoloed ? "headphones.circle.fill" : "headphones"
    }

    private var trackHeaderBackground: LinearGradient {
        LinearGradient(
            colors: [
                CinematicTheme.surfaceContainerLow,
                trackAccentColor.opacity(isArmed ? 0.18 : viewState.selectedTrackID == track.id ? 0.14 : 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var isArmed: Bool {
        viewState.armedTrackID == track.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 3 : 5) {
            HStack(spacing: 5) {
                headerButton(
                    icon: isCollapsed ? "chevron.right" : "chevron.down",
                    isActive: false,
                    tooltip: isCollapsed ? "Expand track header" : "Collapse track header"
                ) {
                    commitTrackNameIfNeeded()
                    appState.toggleTrackCollapse(track.id)
                }

                Image(systemName: trackIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trackAccentColor)

                Text(track.type.rawValue.uppercased())
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))

                Spacer(minLength: 0)

                Text("\(track.clips.count)")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.74))
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(Capsule())
            }

            if !isCollapsed {
                TextField("Track Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CinematicTheme.onSurface)
                    .lineLimit(1)
                    .focused($isNameFocused)
                    .onSubmit(commitTrackName)
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused {
                            commitTrackNameIfNeeded()
                        }
                    }
                    .onChange(of: track.name) { _, newValue in
                        if !isNameFocused && draftName != newValue {
                            draftName = newValue
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: TrackHeaderLayout.textFieldHeight)
                    .background(CinematicTheme.surfaceContainerLowest)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))

                controlsRow
            } else {
                controlsRow
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCollapsed ? 4 : 6)
        .frame(width: TrackHeaderLayout.headerWidth, height: rowHeight, alignment: .topLeading)
        .background(trackHeaderBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.24))
                .frame(width: 1)
        }
        .overlay(alignment: .topTrailing) {
            if viewState.selectedTrackID == track.id {
                Capsule()
                    .fill(CinematicTheme.primary.opacity(0.18))
                    .frame(width: 18, height: 6)
                    .padding(.top, 6)
                    .padding(.trailing, 8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewState.effectiveTargetTrackID == track.id {
                Capsule()
                    .fill(trackAccentColor.opacity(0.28))
                    .frame(width: 18, height: 6)
                    .padding(.bottom, 6)
                    .padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.timelineViewState.selectTrack(track.id)
        }
        .onAppear {
            draftName = resolvedTrackName
        }
        .onChange(of: isCollapsed) { _, _ in
            commitTrackNameIfNeeded()
        }
        .onChange(of: track.name) { _, newValue in
            if !isNameFocused && draftName != newValue {
                draftName = newValue
            }
        }
        .onDisappear {
            commitTrackNameIfNeeded()
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 5) {
            ForEach(headerLayout.inlineControls, id: \.self) { control in
                inlineButton(for: control)
            }

            Spacer(minLength: 0)

            if headerLayout.showsOverflowMenu {
                overflowMenu
            }
        }
    }

    private var resolvedTrackName: String {
        track.name.isEmpty ? "\(track.type.rawValue.capitalized) Track" : track.name
    }

    private var removableAction: (() -> Void)? {
        guard track.clips.isEmpty, !track.isLocked else { return nil }
        return {
            try? appState.perform(.removeTrack(trackID: track.id))
        }
    }

    private func commitTrackName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextName = trimmed.isEmpty ? resolvedTrackName : trimmed
        draftName = nextName
        appState.renameTrack(id: track.id, to: nextName)
        isNameFocused = false
    }

    private func commitTrackNameIfNeeded() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextName = trimmed.isEmpty ? resolvedTrackName : trimmed
        guard nextName != track.name else { return }
        commitTrackName()
    }

    private func headerButton(
        icon: String,
        isActive: Bool,
        isDestructive: Bool = false,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(buttonForeground(isActive: isActive, isDestructive: isDestructive))
                .frame(width: TrackHeaderLayout.controlSize, height: TrackHeaderLayout.controlSize)
                .background(buttonBackground(isActive: isActive, isDestructive: isDestructive))
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    @ViewBuilder
    private func inlineButton(for control: TrackHeaderControl) -> some View {
        switch control {
        case .arm:
            headerButton(
                icon: "target",
                isActive: isArmed,
                tooltip: isArmed ? "Clear destination track" : "Arm destination track"
            ) {
                appState.timelineViewState.toggleArmedTrack(track.id)
            }
        case .mute:
            headerButton(
                icon: muteIcon,
                isActive: !track.isMuted,
                tooltip: track.isMuted ? "Unmute track" : "Mute track"
            ) {
                try? appState.perform(.muteTrack(trackID: track.id, muted: !track.isMuted))
            }
        case .solo:
            headerButton(
                icon: soloIcon,
                isActive: track.isSoloed,
                tooltip: track.isSoloed ? "Clear solo" : "Solo track"
            ) {
                try? appState.perform(.soloTrack(trackID: track.id, soloed: !track.isSoloed))
            }
        case .lock:
            headerButton(
                icon: track.isLocked ? "lock.fill" : "lock.open.fill",
                isActive: track.isLocked,
                tooltip: track.isLocked ? "Unlock track" : "Lock track"
            ) {
                try? appState.perform(.lockTrack(trackID: track.id, locked: !track.isLocked))
            }
        case .addLane, .cycleHeight, .removeTrack:
            EmptyView()
        }
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(headerLayout.overflowControls, id: \.self) { control in
                overflowButton(for: control)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                .frame(width: TrackHeaderLayout.controlSize, height: TrackHeaderLayout.controlSize)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func overflowButton(for control: TrackHeaderControl) -> some View {
        switch control {
        case .addLane:
            Button {
                appState.addTrack(of: track.type, positionedAfter: track.id)
            } label: {
                Label("Add \(track.type.rawValue) lane", systemImage: "plus")
            }
        case .cycleHeight:
            Button {
                appState.cycleTrackHeight(track.id)
            } label: {
                Label("Cycle lane height", systemImage: "arrow.up.and.down.text.horizontal")
            }
        case .removeTrack:
            if let onRemoveTrack = removableAction {
                Button(role: .destructive) {
                    onRemoveTrack()
                } label: {
                    Label("Remove empty track", systemImage: "trash")
                }
            }
        case .arm, .mute, .solo, .lock:
            EmptyView()
        }
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
}
