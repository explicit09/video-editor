import SwiftUI
import EditorCore
import AIServices

/// AI Search Results — Stitch Screen 8: visual search results with timestamps.
/// Displayed in the Inspector panel when search results are available.
struct SearchResultsView: View {
    let query: String
    let results: [SearchResult]
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(CinematicTheme.primary)
                Text("AI Insights")
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.onSurface)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CinematicTheme.surfaceContainer)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Search query
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                Text(query)
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurface)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Results count
            Text("\(results.count) MATCHES FOUND")
                .font(.cinLabel)
                .tracking(1)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Results list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results) { result in
                        searchResultRow(result)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            // AI suggestion
            if results.count > 1 {
                aiSuggestion
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    /// Create a new track with clips at each search result timestamp.
    private func createSequenceFromResults() {
        let track = Track(name: "\(query) sequence", type: .video)
        try? appState.perform(.addTrack(track: track))

        var position: TimeInterval = 0
        let clipDuration: TimeInterval = 5 // 5 seconds around each match

        for result in results {
            let sourceStart = max(0, result.matchTime - 1) // 1s before match
            let clip = Clip(
                assetID: result.assetID,
                timelineRange: TimeRange(start: position, duration: clipDuration),
                sourceRange: TimeRange(start: sourceStart, duration: clipDuration),
                metadata: ClipMetadata(label: "\(result.formattedTime) — \(query)")
            )
            try? appState.perform(.insertClip(clip: clip, trackID: track.id))
            position += clipDuration
        }
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        Button(action: {
            // Seek to match time
            appState.playbackEngine.seek(to: result.matchTime)
            appState.timelineViewState.playheadPosition = result.matchTime
        }) {
            HStack(alignment: .top, spacing: 10) {
                // Timestamp
                Text(result.formattedTime)
                    .font(.cinTimecode)
                    .foregroundStyle(CinematicTheme.primary)
                    .frame(width: 50, alignment: .leading)

                // Context text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(result.contextText)\"")
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurface.opacity(0.8))
                        .lineLimit(3)
                        .italic()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CinematicTheme.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var aiSuggestion: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.primary)
                Text("AI SUGGESTION")
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.primary)
            }

            Text("I've noticed \(results.count) clips with '\(query)' mentions. Would you like to create a sub-sequence of these moments?")
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))

            Button(action: createSequenceFromResults) {
                Text("Create Sequence")
                    .font(.cinTitleSmall)
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(CinematicTheme.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(CinematicTheme.primaryContainer.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}
