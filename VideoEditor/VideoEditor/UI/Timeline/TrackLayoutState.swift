import Foundation
import EditorCore

@MainActor @Observable
final class TrackLayoutState {
    enum RowHeightMode: CaseIterable {
        case compact
        case standard
        case expanded
    }

    let collapsedTrackHeight: Double = 28
    let compactTrackHeight: Double = 56
    let expandedTrackHeight: Double = 84
    let detailTrackHeight: Double = 120

    var collapsedTrackIDs: Set<UUID> = []
    private var rowHeightModes: [UUID: RowHeightMode] = [:]

    func height(for track: Track) -> Double {
        height(for: track.id)
    }

    func height(for trackID: UUID) -> Double {
        guard !collapsedTrackIDs.contains(trackID) else { return collapsedTrackHeight }

        switch rowHeightMode(for: trackID) {
        case .compact:
            return compactTrackHeight
        case .standard:
            return expandedTrackHeight
        case .expanded:
            return detailTrackHeight
        }
    }

    func isCollapsed(_ trackID: UUID) -> Bool {
        collapsedTrackIDs.contains(trackID)
    }

    func rowHeightMode(for trackID: UUID) -> RowHeightMode {
        rowHeightModes[trackID] ?? .standard
    }

    func toggleCollapse(_ trackID: UUID) {
        if !collapsedTrackIDs.insert(trackID).inserted {
            collapsedTrackIDs.remove(trackID)
        }
    }

    func cycleHeight(for trackID: UUID) {
        let allModes = RowHeightMode.allCases
        let currentMode = rowHeightMode(for: trackID)
        guard let currentIndex = allModes.firstIndex(of: currentMode) else { return }
        let nextIndex = (currentIndex + 1) % allModes.count
        rowHeightModes[trackID] = allModes[nextIndex]
    }

    func yOffset(for trackIndex: Int, in tracks: [Track], rowSpacing: Double) -> Double {
        guard trackIndex > 0, tracks.indices.contains(trackIndex) else { return 8 }

        var offset = 8.0
        for priorIndex in tracks.indices where priorIndex < trackIndex {
            offset += height(for: tracks[priorIndex]) + rowSpacing
        }
        return offset
    }

    func totalContentHeight(for tracks: [Track], rowSpacing: Double) -> Double {
        guard !tracks.isEmpty else { return 0 }
        let totalRows = tracks.reduce(0) { $0 + height(for: $1) }
        let totalGaps = Double(max(tracks.count - 1, 0)) * rowSpacing
        return totalRows + totalGaps + 16
    }

    func timelineEntries(for tracks: [Track]) -> [TimelineTrackLayoutEntry] {
        tracks.map { track in
            TimelineTrackLayoutEntry(
                id: track.id,
                type: track.type,
                isLocked: track.isLocked,
                height: height(for: track)
            )
        }
    }
}
