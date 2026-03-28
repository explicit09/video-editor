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
            if let transcript = activeTranscript {
                transcriptContent(transcript)
            } else {
                emptyState
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    // MARK: - Active transcript + offset

    /// The time offset to convert source media time → timeline time.
    /// Source time + offset = timeline time.
    private var transcriptTimeOffset: TimeInterval {
        if let clip = activeClip {
            // Clip sits at timelineRange.start, referencing sourceRange.start
            // So source time T maps to timeline time: T - sourceRange.start + timelineRange.start
            return clip.timelineRange.start - clip.sourceRange.start
        }
        return 0
    }

    /// The clip whose asset provides the active transcript.
    private var activeClip: Clip? {
        if let selectedID = appState.timelineViewState.selectedClipIDs.first,
           let clip = appState.timeline.tracks.flatMap(\.clips).first(where: { $0.id == selectedID }),
           let asset = appState.assets.first(where: { $0.id == clip.assetID }),
           let words = asset.analysis?.transcript, !words.isEmpty {
            return clip
        }

        // Fallback: first clip on timeline with a transcript
        for clip in appState.timeline.tracks.flatMap(\.clips) {
            if let asset = appState.assets.first(where: { $0.id == clip.assetID }),
               let words = asset.analysis?.transcript, !words.isEmpty {
                return clip
            }
        }
        return nil
    }

    /// Find the transcript for the active clip's asset.
    private var activeTranscript: [TranscriptWord]? {
        guard let clip = activeClip,
              let asset = appState.assets.first(where: { $0.id == clip.assetID }),
              let words = asset.analysis?.transcript, !words.isEmpty else {
            return nil
        }
        return words
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 12))
                        .foregroundStyle(CinematicTheme.primary)
                    Text("TRANSCRIPT")
                        .font(.cinLabel)
                        .tracking(1.5)
                        .foregroundStyle(CinematicTheme.onSurface)
                }
                Spacer()
            }

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurface)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CinematicTheme.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CinematicTheme.surfaceContainer)
    }

    // MARK: - Transcript content

    private func transcriptContent(_ words: [TranscriptWord]) -> some View {
        let offset = transcriptTimeOffset
        let segments = groupIntoSegments(words, timeOffset: offset)
        let playhead = appState.playbackEngine.currentTime

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments.indices, id: \.self) { i in
                        let segment = segments[i]
                        let isActive = playhead >= segment.startTime && playhead < segment.endTime

                        transcriptSegment(segment, isActive: isActive, matches: matchesSearch(segment))
                            .id(i)
                    }
                }
                .padding(16)
            }
            .onChange(of: appState.playbackEngine.currentTime) { _, newTime in
                // Auto-scroll to active segment
                if let idx = segments.firstIndex(where: { newTime >= $0.startTime && newTime < $0.endTime }) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private func transcriptSegment(_ segment: TranscriptSegmentGroup, isActive: Bool, matches: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(TimeFormatter.duration(segment.startTime))
                .font(.cinLabel)
                .foregroundStyle(isActive ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.4))
                .frame(width: 45, alignment: .trailing)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(highlightedText(segment.text, query: searchQuery, isActive: isActive))
                    .font(.cinBody)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isActive
                ? CinematicTheme.primaryContainer.opacity(0.08)
                : (matches && !searchQuery.isEmpty ? CinematicTheme.primary.opacity(0.05) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        .contentShape(Rectangle())
        .onTapGesture {
            // Seek to segment start
            appState.playbackEngine.seek(to: segment.startTime)
            appState.timelineViewState.playheadPosition = segment.startTime
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.alignleft")
                .font(.system(size: 28))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
            Text("No transcript available")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
            Text("Ask AI to transcribe your video")
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Group words into ~12-word segments. Times are adjusted by offset to match timeline.
    private func groupIntoSegments(_ words: [TranscriptWord], timeOffset: TimeInterval = 0) -> [TranscriptSegmentGroup] {
        var segments: [TranscriptSegmentGroup] = []
        let chunkSize = 12

        for start in stride(from: 0, to: words.count, by: chunkSize) {
            let end = min(start + chunkSize, words.count)
            let chunk = Array(words[start..<end])
            let text = chunk.map(\.word).joined(separator: " ")
            let startTime = (chunk.first?.start ?? 0) + timeOffset
            let endTime = (chunk.last?.end ?? 0) + timeOffset
            segments.append(TranscriptSegmentGroup(text: text, startTime: startTime, endTime: endTime))
        }

        return segments
    }

    private func highlightedText(_ text: String, query: String, isActive: Bool) -> AttributedString {
        let baseColor = isActive ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.7)
        var attributed = AttributedString(text)
        attributed.foregroundColor = baseColor

        guard !query.isEmpty else { return attributed }

        // Find and highlight all occurrences of the query
        var searchStart = text.startIndex
        let lowered = text.lowercased()
        let queryLowered = query.lowercased()

        while let range = lowered.range(of: queryLowered, range: searchStart..<lowered.endIndex) {
            // Convert String range to AttributedString range
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

// MARK: - Segment grouping

struct TranscriptSegmentGroup {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
