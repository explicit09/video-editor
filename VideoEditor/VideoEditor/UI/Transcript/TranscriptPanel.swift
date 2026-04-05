import SwiftUI
import EditorCore
import AIServices

/// Transcript view with text-based editing — edit video by editing the transcript.
/// Supports word-level selection, filler word highlighting, speaker labels,
/// and delete/remove-fillers actions.
struct TranscriptPanel: View {
    @Environment(AppState.self) private var appState
    @State private var searchQuery = ""
    @State private var selectedWordRange: Range<Int>?
    @State private var selectionAnchor: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let context = transcriptContext {
                transcriptContent(context)
            } else {
                emptyState
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    // MARK: - Active transcript context

    private var transcriptContext: TranscriptContext? {
        let playhead = appState.playbackEngine.currentTime
        let selectedIDs = appState.timelineViewState.selectedClipIDs

        struct Candidate {
            let priority: Int
            let distance: TimeInterval
            let clip: Clip
            let trackID: UUID
            let asset: MediaAsset
        }

        var candidates: [Candidate] = []

        for track in appState.timeline.tracks {
            for clip in track.clips {
                guard let asset = appState.assets.first(where: { $0.id == clip.assetID }),
                      let words = asset.analysis?.transcript,
                      !words.isEmpty else {
                    continue
                }

                let priority: Int
                if clip.timelineRange.contains(playhead) {
                    priority = 0
                } else if selectedIDs.contains(clip.id) {
                    priority = 1
                } else {
                    priority = 2
                }

                candidates.append(
                    Candidate(
                        priority: priority,
                        distance: abs(clip.timelineRange.start - playhead),
                        clip: clip,
                        trackID: track.id,
                        asset: asset
                    )
                )
            }
        }

        guard let candidate = candidates.sorted(by: {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.distance < $1.distance
        }).first else {
            return nil
        }

        let visibleWords = (candidate.asset.analysis?.transcript ?? []).filter {
            $0.end > candidate.clip.sourceRange.start && $0.start < candidate.clip.sourceRange.end
        }
        guard !visibleWords.isEmpty else { return nil }

        return TranscriptContext(
            clip: candidate.clip,
            trackID: candidate.trackID,
            asset: candidate.asset,
            words: visibleWords
        )
    }

    // MARK: - Header

    private var header: some View {
        let context = transcriptContext
        let fillerCount = context.map { $0.words.filter { isFiller($0.word) }.count } ?? 0

        return VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "TRANSCRIPT",
                title: "Text Edit",
                subtitle: "Select words to delete sections or remove filler words",
                badgeCount: context == nil ? 0 : 1,
                showsPrimaryAction: fillerCount > 0,
                trailingAccessory: { layout in
                    if let context {
                        HStack(spacing: 8) {
                            if layout.showsPrimaryAction {
                                UtilityHeaderButton(
                                    icon: "wand.and.stars",
                                    title: layout.showsSecondaryBadges ? "Remove Fillers (\(fillerCount))" : nil,
                                    isProminent: true,
                                    action: { removeAllFillers(context) }
                                )
                                .disabled(fillerCount == 0)
                            }

                            if layout.showsSecondaryBadges {
                                UtilityHeaderBadge(
                                    text: context.clip.metadata.label ?? context.asset.name,
                                    systemImage: "waveform.and.mic",
                                    style: .info
                                )
                            }
                        }
                    }
                }
            )

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurface)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CinematicTheme.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(CinematicTheme.surfaceContainer)
    }

    // MARK: - Transcript content

    private func transcriptContent(_ context: TranscriptContext) -> some View {
        let segments = groupIntoSegments(context.words, clip: context.clip)
        let playhead = appState.playbackEngine.currentTime
        let speakers = context.asset.analysis?.speakerSegments

        return ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(segments.indices, id: \.self) { i in
                            let segment = segments[i]
                            let isActive = playhead >= segment.startTime && playhead < segment.endTime

                            wordFlowSegment(
                                segment,
                                isActive: isActive,
                                playhead: playhead,
                                context: context,
                                speakers: speakers
                            )
                            .id(i)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, selectedWordRange != nil ? 56 : 0)
                }
                .onChange(of: appState.playbackEngine.currentTime) { _, newTime in
                    if let idx = segments.firstIndex(where: { newTime >= $0.startTime && newTime < $0.endTime }) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }

            if selectedWordRange != nil {
                selectionToolbar(context)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedWordRange != nil)
    }

    // MARK: - Word flow segment

    private func wordFlowSegment(
        _ segment: TranscriptSegmentGroup,
        isActive: Bool,
        playhead: TimeInterval,
        context: TranscriptContext,
        speakers: [SpeakerSegment]?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(TimeFormatter.duration(segment.startTime))
                .font(.cinLabel)
                .foregroundStyle(isActive ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.4))
                .frame(width: 45, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                // Speaker label at segment start if speaker changed
                if let label = speakerLabel(at: segment.globalStartIndex, words: context.words, speakers: speakers) {
                    Text(label)
                        .font(.cinLabel)
                        .tracking(1.2)
                        .foregroundStyle(CinematicTheme.tertiary.opacity(0.8))
                        .padding(.bottom, 2)
                }

                wordFlowLayout(segment: segment, playhead: playhead, context: context)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isActive
                ? CinematicTheme.primaryContainer.opacity(0.12)
                : (matchesSearch(segment) && !searchQuery.isEmpty ? CinematicTheme.primary.opacity(0.05) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .strokeBorder(
                    isActive ? CinematicTheme.primary.opacity(0.24) : CinematicTheme.outlineVariant.opacity(matchesSearch(segment) ? 0.18 : 0.08),
                    lineWidth: isActive ? 1 : 0.5
                )
        )
    }

    // MARK: - Word flow layout (wrapping words)

    private func wordFlowLayout(segment: TranscriptSegmentGroup, playhead: TimeInterval, context: TranscriptContext) -> some View {
        FlowLayout(spacing: 3) {
            ForEach(segment.mappedWords.indices, id: \.self) { i in
                let mapped = segment.mappedWords[i]
                let globalIdx = segment.globalStartIndex + i
                let isActiveWord = playhead >= mapped.timelineStart && playhead < mapped.timelineEnd
                let isSelected = isWordSelected(globalIdx)
                let filler = isFiller(mapped.text)

                wordView(
                    text: mapped.text,
                    isActiveWord: isActiveWord,
                    isSelected: isSelected,
                    isFiller: filler,
                    matchesSearch: !searchQuery.isEmpty && mapped.text.localizedCaseInsensitiveContains(searchQuery)
                )
                .onTapGesture {
                    handleWordTap(globalIdx: globalIdx, context: context)
                }
            }
        }
    }

    // MARK: - Individual word view

    private func wordView(
        text: String,
        isActiveWord: Bool,
        isSelected: Bool,
        isFiller: Bool,
        matchesSearch: Bool
    ) -> some View {
        Text(text)
            .font(.cinBody)
            .foregroundStyle(wordForeground(isActiveWord: isActiveWord, isSelected: isSelected, isFiller: isFiller, matchesSearch: matchesSearch))
            .strikethrough(isFiller && !isSelected, color: CinematicTheme.onSurfaceVariant.opacity(0.3))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(wordBackground(isActiveWord: isActiveWord, isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.xs))
            .contentShape(Rectangle())
    }

    private func wordForeground(isActiveWord: Bool, isSelected: Bool, isFiller: Bool, matchesSearch: Bool) -> Color {
        if isSelected { return CinematicTheme.onPrimaryContainer }
        if isActiveWord { return CinematicTheme.primary }
        if matchesSearch { return CinematicTheme.primary }
        if isFiller { return CinematicTheme.onSurfaceVariant.opacity(0.4) }
        return CinematicTheme.onSurfaceVariant.opacity(0.7)
    }

    private func wordBackground(isActiveWord: Bool, isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(CinematicTheme.primaryContainer.opacity(0.5))
        }
        if isActiveWord {
            return AnyShapeStyle(CinematicTheme.primaryContainer.opacity(0.15))
        }
        return AnyShapeStyle(Color.clear)
    }

    // MARK: - Selection handling

    private func isWordSelected(_ globalIdx: Int) -> Bool {
        guard let range = selectedWordRange else { return false }
        return range.contains(globalIdx)
    }

    private func handleWordTap(globalIdx: Int, context: TranscriptContext) {
        if NSEvent.modifierFlags.contains(.shift), let anchor = selectionAnchor {
            // Shift-click: extend selection from anchor
            let lower = min(anchor, globalIdx)
            let upper = max(anchor, globalIdx) + 1
            selectedWordRange = lower..<upper
        } else {
            // Single click: seek to word time and start new selection anchor
            let word = context.words[globalIdx]
            let timelineTime = word.start - context.clip.sourceRange.start + context.clip.timelineRange.start
            appState.focusTimeline(at: timelineTime, clipID: context.clip.id, trackID: context.trackID)

            selectionAnchor = globalIdx
            selectedWordRange = globalIdx..<(globalIdx + 1)
        }
    }

    private func clearSelection() {
        selectedWordRange = nil
        selectionAnchor = nil
    }

    // MARK: - Selection toolbar

    private func selectionToolbar(_ context: TranscriptContext) -> some View {
        let wordCount = selectedWordRange.map(\.count) ?? 0
        let hasFillersInSelection = selectedWordRange.map { range in
            range.contains(where: { isFiller(context.words[$0].word) })
        } ?? false

        return HStack(spacing: 10) {
            Text("\(wordCount) word\(wordCount == 1 ? "" : "s") selected")
                .font(.cinLabel)
                .foregroundStyle(CinematicTheme.onSurfaceVariant)

            Spacer()

            if hasFillersInSelection {
                CinematicToolbarButton(
                    icon: "wand.and.stars",
                    label: "Remove Fillers",
                    action: { removeAllFillers(context) }
                )
            }

            CinematicToolbarButton(
                icon: "trash",
                label: "Delete",
                isDestructive: true,
                action: { deleteSelectedWords(context) }
            )

            CinematicToolbarButton(
                icon: "xmark",
                action: { clearSelection() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CinematicTheme.surfaceContainerHighest)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(CinematicTheme.outlineVariant.opacity(0.2)),
            alignment: .top
        )
    }

    // MARK: - Delete action

    private func deleteSelectedWords(_ context: TranscriptContext) {
        guard let range = selectedWordRange, !range.isEmpty else { return }
        let startWord = context.words[range.lowerBound]
        let endWord = context.words[range.upperBound - 1]

        let sourceStart = startWord.start
        let sourceEnd = endWord.end
        let assetID = context.asset.id

        let deleteRange = TimeRange(start: sourceStart, end: sourceEnd)

        // Rebuild timeline excluding this source range (same approach as MCP delete_transcript_range)
        rebuildTimelineExcludingSourceRange(assetID: assetID, deleteRange: deleteRange)
        clearSelection()
    }

    // MARK: - Remove all fillers

    private func removeAllFillers(_ context: TranscriptContext) {
        let fillerWordRanges = context.words.enumerated().compactMap { idx, word -> (start: TimeInterval, end: TimeInterval)? in
            guard isFiller(word.word) else { return nil }
            return (start: word.start, end: word.end)
        }

        guard !fillerWordRanges.isEmpty else { return }

        let assetID = context.asset.id

        // Remove fillers from last to first so timeline offsets don't shift
        for filler in fillerWordRanges.reversed() {
            let deleteRange = TimeRange(start: filler.start, end: filler.end)
            rebuildTimelineExcludingSourceRange(assetID: assetID, deleteRange: deleteRange)
        }

        clearSelection()
    }

    // MARK: - Timeline rebuild (mirrors MCPServer.rebuildTimelineExcludingSourceRange)

    private func rebuildTimelineExcludingSourceRange(assetID: UUID, deleteRange: TimeRange) {
        var allClipsForAsset: [(clip: Clip, trackIdx: Int)] = []
        for (trackIdx, track) in appState.timeline.tracks.enumerated() {
            for clip in track.clips where clip.assetID == assetID {
                allClipsForAsset.append((clip: clip, trackIdx: trackIdx))
            }
        }

        guard !allClipsForAsset.isEmpty else { return }

        // Group clips by linkGroupID (video+audio pairs)
        var processedLinks = Set<UUID>()
        var clipGroups: [[(clip: Clip, trackIdx: Int)]] = []
        for entry in allClipsForAsset {
            if let linkID = entry.clip.linkGroupID, processedLinks.contains(linkID) { continue }
            if let linkID = entry.clip.linkGroupID {
                processedLinks.insert(linkID)
                let group = allClipsForAsset.filter { $0.clip.linkGroupID == linkID }
                clipGroups.append(group)
            } else {
                clipGroups.append([entry])
            }
        }

        for group in clipGroups {
            guard let primary = group.first else { continue }
            let clipSourceRange = primary.clip.sourceRange
            guard clipSourceRange.overlaps(deleteRange) else { continue }

            var keepRanges: [TimeRange] = []
            if clipSourceRange.start < deleteRange.start {
                keepRanges.append(TimeRange(start: clipSourceRange.start, end: min(deleteRange.start, clipSourceRange.end)))
            }
            if clipSourceRange.end > deleteRange.end {
                keepRanges.append(TimeRange(start: max(deleteRange.end, clipSourceRange.start), end: clipSourceRange.end))
            }

            do {
                let idsToDelete = group.map { $0.clip.id }
                try appState.perform(.deleteClips(clipIDs: idsToDelete), source: .user)

                let originalTimelineStart = primary.clip.timelineRange.start
                var timelineCursor = originalTimelineStart
                for keep in keepRanges {
                    let duration = keep.duration
                    let linkID = UUID()
                    for entry in group {
                        let newClip = Clip(
                            assetID: assetID,
                            timelineRange: TimeRange(start: timelineCursor, duration: duration),
                            sourceRange: keep,
                            volume: entry.clip.volume,
                            speed: entry.clip.speed,
                            linkGroupID: group.count > 1 ? linkID : entry.clip.linkGroupID
                        )
                        try appState.perform(.insertClip(clip: newClip, trackID: appState.timeline.tracks[entry.trackIdx].id), source: .user)
                    }
                    timelineCursor += duration
                }
            } catch {
                // Fail silently — clip may have already been removed
            }
        }

        appState.rebuildComposition()
    }

    // MARK: - Speaker labels

    private func speakerLabel(at globalWordIndex: Int, words: [TranscriptWord], speakers: [SpeakerSegment]?) -> String? {
        guard let speakers = speakers, !speakers.isEmpty else { return nil }
        guard globalWordIndex < words.count else { return nil }

        let wordTime = words[globalWordIndex].start
        let currentSpeaker = speakers.last(where: { $0.range.start <= wordTime })

        // Only show label at the start or when speaker changes from previous word
        if globalWordIndex == 0 {
            return currentSpeaker.map { "Speaker \($0.speakerID)" }
        }

        let prevWordTime = words[globalWordIndex - 1].start
        let prevSpeaker = speakers.last(where: { $0.range.start <= prevWordTime })

        if currentSpeaker?.speakerID != prevSpeaker?.speakerID {
            return currentSpeaker.map { "Speaker \($0.speakerID)" }
        }

        return nil
    }

    // MARK: - Filler word detection

    private static let fillerWords: Set<String> = [
        "um", "uh", "like", "you know", "so", "basically", "actually", "right", "i mean"
    ]

    private func isFiller(_ word: String) -> Bool {
        Self.fillerWords.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            CinematicEmptyStateBlock(
                icon: "text.alignleft",
                title: "No transcript available",
                detail: "Select a clip with transcript data, or run transcription on a source to make spoken content searchable."
            ) {
                UtilityStatusBadge(text: "Use AI to transcribe", icon: "sparkles", style: .accent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Group transcript words into visible timeline segments for the active clip only.
    private func groupIntoSegments(_ words: [TranscriptWord], clip: Clip) -> [TranscriptSegmentGroup] {
        var segments: [TranscriptSegmentGroup] = []
        let chunkSize = 12

        for start in stride(from: 0, to: words.count, by: chunkSize) {
            let end = min(start + chunkSize, words.count)
            let chunk = Array(words[start..<end])
            let mappedWords = chunk.compactMap { word -> MappedWord? in
                let visibleStart = max(word.start, clip.sourceRange.start)
                let visibleEnd = min(word.end, clip.sourceRange.end)
                guard visibleEnd > visibleStart else { return nil }

                return MappedWord(
                    text: word.word,
                    sourceStart: word.start,
                    sourceEnd: word.end,
                    timelineStart: visibleStart - clip.sourceRange.start + clip.timelineRange.start,
                    timelineEnd: visibleEnd - clip.sourceRange.start + clip.timelineRange.start
                )
            }

            guard let firstWord = mappedWords.first, let lastWord = mappedWords.last else { continue }
            segments.append(
                TranscriptSegmentGroup(
                    text: mappedWords.map(\.text).joined(separator: " "),
                    startTime: firstWord.timelineStart,
                    endTime: lastWord.timelineEnd,
                    mappedWords: mappedWords,
                    globalStartIndex: start
                )
            )
        }

        return segments
    }

    private func matchesSearch(_ segment: TranscriptSegmentGroup) -> Bool {
        guard !searchQuery.isEmpty else { return false }
        return segment.text.localizedCaseInsensitiveContains(searchQuery)
    }
}

// MARK: - Supporting types

private struct TranscriptContext {
    let clip: Clip
    let trackID: UUID
    let asset: MediaAsset
    let words: [TranscriptWord]
}

struct MappedWord {
    let text: String
    let sourceStart: TimeInterval
    let sourceEnd: TimeInterval
    let timelineStart: TimeInterval
    let timelineEnd: TimeInterval
}

struct TranscriptSegmentGroup {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let mappedWords: [MappedWord]
    let globalStartIndex: Int
}

// MARK: - Flow layout for wrapping words

private struct FlowLayout: Layout {
    var spacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }

        let height = rows.reduce(CGFloat(0)) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = rows[rows.count - 1].width + (rows[rows.count - 1].items.isEmpty ? 0 : spacing) + size.width

            if neededWidth > maxWidth && !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }

            rows[rows.count - 1].items.append(RowItem(index: index, size: size))
            rows[rows.count - 1].width += (rows[rows.count - 1].items.count > 1 ? spacing : 0) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }

        return rows
    }
}
