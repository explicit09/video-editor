import SwiftUI
import EditorCore
import AIServices

/// Transcript view — shows transcribed text synced with the timeline playhead.
/// Matches Stitch Screen 5: scrollable transcript with timestamps and AI insights.
struct TranscriptPanel: View {
    @Environment(AppState.self) private var appState
    @State private var searchQuery = ""

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
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "TRANSCRIPT",
                title: "Dialogue View",
                subtitle: "Search transcript segments and jump directly to moments in the edit",
                trailingAccessory: {
                    if let context = transcriptContext {
                        CinematicStatusPill(
                            text: context.clip.metadata.label ?? context.asset.name,
                            icon: "waveform.and.mic",
                            tone: CinematicTheme.primary
                        )
                    }
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

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

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments.indices, id: \.self) { i in
                        let segment = segments[i]
                        let isActive = playhead >= segment.startTime && playhead < segment.endTime

                        transcriptSegment(segment, isActive: isActive, matches: matchesSearch(segment)) {
                            appState.focusTimeline(at: segment.startTime, clipID: context.clip.id, trackID: context.trackID)
                        }
                        .id(i)
                    }
                }
                .padding(16)
            }
            .onChange(of: appState.playbackEngine.currentTime) { _, newTime in
                if let idx = segments.firstIndex(where: { newTime >= $0.startTime && newTime < $0.endTime }) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private func transcriptSegment(
        _ segment: TranscriptSegmentGroup,
        isActive: Bool,
        matches: Bool,
        onJump: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(TimeFormatter.duration(segment.startTime))
                .font(.cinLabel)
                .foregroundStyle(isActive ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.4))
                .frame(width: 45, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedText(segment.text, query: searchQuery, isActive: isActive))
                    .font(.cinBody)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isActive
                ? CinematicTheme.primaryContainer.opacity(0.12)
                : (matches && !searchQuery.isEmpty ? CinematicTheme.primary.opacity(0.05) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .strokeBorder(
                    isActive ? CinematicTheme.primary.opacity(0.24) : CinematicTheme.outlineVariant.opacity(matches ? 0.18 : 0.08),
                    lineWidth: isActive ? 1 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
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
                CinematicStatusPill(text: "Use AI to transcribe", icon: "sparkles", tone: CinematicTheme.primary)
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
            let mappedWords = chunk.compactMap { word -> TimelineTranscriptWord? in
                let visibleStart = max(word.start, clip.sourceRange.start)
                let visibleEnd = min(word.end, clip.sourceRange.end)
                guard visibleEnd > visibleStart else { return nil }

                return TimelineTranscriptWord(
                    text: word.word,
                    start: visibleStart - clip.sourceRange.start + clip.timelineRange.start,
                    end: visibleEnd - clip.sourceRange.start + clip.timelineRange.start
                )
            }

            guard let firstWord = mappedWords.first, let lastWord = mappedWords.last else { continue }
            segments.append(
                TranscriptSegmentGroup(
                    text: mappedWords.map(\.text).joined(separator: " "),
                    startTime: firstWord.start,
                    endTime: lastWord.end
                )
            )
        }

        return segments
    }

    private func highlightedText(_ text: String, query: String, isActive: Bool) -> AttributedString {
        let baseColor = isActive ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.7)
        var attributed = AttributedString(text)
        attributed.foregroundColor = baseColor

        guard !query.isEmpty else { return attributed }

        var searchStart = text.startIndex
        let lowered = text.lowercased()
        let queryLowered = query.lowercased()

        while let range = lowered.range(of: queryLowered, range: searchStart..<lowered.endIndex) {
            if let attrRange = Range<AttributedString.Index>(range, in: attributed) {
                attributed[attrRange].foregroundColor = CinematicTheme.primary
                attributed[attrRange].font = .cinTitleSmall
            }
            searchStart = range.upperBound
        }

        return attributed
    }

    private func matchesSearch(_ segment: TranscriptSegmentGroup) -> Bool {
        guard !searchQuery.isEmpty else { return false }
        return segment.text.localizedCaseInsensitiveContains(searchQuery)
    }
}

private struct TranscriptContext {
    let clip: Clip
    let trackID: UUID
    let asset: MediaAsset
    let words: [TranscriptWord]
}

private struct TimelineTranscriptWord {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct TranscriptSegmentGroup {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
