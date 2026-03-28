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

    // MARK: - Active transcript

    /// Find the transcript for the first asset on the timeline (or selected clip's asset).
    private var activeTranscript: [TranscriptWord]? {
        // Prefer selected clip's asset
        if let selectedID = appState.timelineViewState.selectedClipIDs.first,
           let clip = appState.timeline.tracks.flatMap(\.clips).first(where: { $0.id == selectedID }),
           let asset = appState.assets.first(where: { $0.id == clip.assetID }),
           let words = asset.analysis?.transcript, !words.isEmpty {
            return words
        }

        // Fallback: first asset with a transcript
        for asset in appState.assets {
            if let words = asset.analysis?.transcript, !words.isEmpty {
                return words
            }
        }
        return nil
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
        let segments = groupIntoSegments(words)
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
            Text(formatTime(segment.startTime))
                .font(.cinLabel)
                .foregroundStyle(isActive ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.4))
                .frame(width: 45, alignment: .trailing)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .font(.cinBody)
                    .foregroundStyle(isActive ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.7))
                    .lineSpacing(4)

                // Highlight matching text
                if matches && !searchQuery.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("Match found")
                            .font(.cinLabelRegular)
                    }
                    .foregroundStyle(CinematicTheme.primary.opacity(0.7))
                }
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

    /// Group words into ~10-word segments for readable paragraphs.
    private func groupIntoSegments(_ words: [TranscriptWord]) -> [TranscriptSegmentGroup] {
        var segments: [TranscriptSegmentGroup] = []
        let chunkSize = 12

        for start in stride(from: 0, to: words.count, by: chunkSize) {
            let end = min(start + chunkSize, words.count)
            let chunk = Array(words[start..<end])
            let text = chunk.map(\.word).joined(separator: " ")
            let startTime = chunk.first?.start ?? 0
            let endTime = chunk.last?.end ?? 0
            segments.append(TranscriptSegmentGroup(text: text, startTime: startTime, endTime: endTime))
        }

        return segments
    }

    private func matchesSearch(_ segment: TranscriptSegmentGroup) -> Bool {
        guard !searchQuery.isEmpty else { return false }
        return segment.text.localizedCaseInsensitiveContains(searchQuery)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Segment grouping

struct TranscriptSegmentGroup {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
