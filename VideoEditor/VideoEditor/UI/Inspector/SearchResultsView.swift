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
            UtilityPanelHeader(
                eyebrow: "AI SEARCH",
                title: "Search Results",
                subtitle: "\"\(query)\"",
                badgeCount: 1,
                showsPrimaryAction: false,
                trailingAccessory: { _ in
                    UtilityStatusBadge(
                        text: "\(results.count) matches",
                        icon: "sparkles.rectangle.stack",
                        isAccent: true
                    )
                }
            )

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results) { result in
                        searchResultRow(result)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            if results.count > 1 {
                aiSuggestion
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private func createSequenceFromResults() {
        Task { @MainActor in
            await appState.createSearchSequence(from: results, named: query)
        }
    }

    private func timelinePlacement(for result: SearchResult) -> (clipID: UUID, trackID: UUID, timelineTime: TimeInterval)? {
        appState.timelineLocation(forAssetID: result.assetID, sourceTime: result.matchTime)
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        let placement = timelinePlacement(for: result)

        return Button(action: {
            guard let placement else { return }
            appState.focusTimeline(at: placement.timelineTime, clipID: placement.clipID, trackID: placement.trackID)
        }) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.formattedTime)
                        .font(.cinTimecode)
                        .foregroundStyle(placement == nil ? CinematicTheme.onSurfaceVariant.opacity(0.45) : CinematicTheme.primary)

                    UtilityStatusBadge(
                        text: placement == nil ? "Source Only" : "On Timeline",
                        icon: placement == nil ? "tray" : "timeline.selection",
                        isAccent: placement != nil
                    )
                }
                .frame(width: 88, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.assetName)
                        .font(.cinLabel)
                        .tracking(0.8)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))

                    Text("\"\(result.contextText)\"")
                        .font(.cinBody)
                        .foregroundStyle(CinematicTheme.onSurface.opacity(placement == nil ? 0.54 : 0.86))
                        .lineLimit(3)
                        .italic()
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [CinematicTheme.surfaceContainerLowest, CinematicTheme.surfaceContainerHigh.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(placement == nil)
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
