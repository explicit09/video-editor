import Foundation
import EditorCore

@MainActor @Observable
final class TrackLayoutState {
    let collapsedTrackHeight: Double = 28
    let expandedTrackHeight: Double = 84

    var collapsedTrackIDs: Set<UUID> = []

    func height(for track: Track) -> Double {
        height(for: track.id)
    }

    func height(for trackID: UUID) -> Double {
        collapsedTrackIDs.contains(trackID) ? collapsedTrackHeight : expandedTrackHeight
    }

    func isCollapsed(_ trackID: UUID) -> Bool {
        collapsedTrackIDs.contains(trackID)
    }

    func toggleCollapse(_ trackID: UUID) {
        if !collapsedTrackIDs.insert(trackID).inserted {
            collapsedTrackIDs.remove(trackID)
        }
    }

    func cycleHeight(for trackID: UUID) {
        toggleCollapse(trackID)
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
