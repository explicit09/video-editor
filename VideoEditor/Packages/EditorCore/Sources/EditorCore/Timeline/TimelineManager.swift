import Foundation

/// Owns all timeline state. Single writer for tracks, clips, and markers.
public actor TimelineManager {
    public private(set) var timeline: Timeline

    public init(timeline: Timeline = Timeline()) {
        self.timeline = timeline
    }

    // MARK: - Timeline mutations

    public func setTimeline(_ timeline: Timeline) {
        self.timeline = timeline
    }

    // MARK: - Track operations

    public func addTrack(_ track: Track) {
        timeline.tracks.append(track)
    }

    public func removeTrack(id: UUID) {
        timeline.tracks.removeAll { $0.id == id }
    }

    public func track(id: UUID) -> Track? {
        timeline.tracks.first { $0.id == id }
    }

    // MARK: - Clip operations

    public func addClip(_ clip: Clip, toTrack trackID: UUID) {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        timeline.tracks[index].clips.append(clip)
    }

    public func removeClip(id: UUID) {
        for i in timeline.tracks.indices {
            timeline.tracks[i].clips.removeAll { $0.id == id }
        }
    }

    public func clip(id: UUID) -> Clip? {
        timeline.tracks.flatMap(\.clips).first { $0.id == id }
    }

    public func updateClip(id: UUID, _ transform: (inout Clip) -> Void) {
        for trackIndex in timeline.tracks.indices {
            if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                transform(&timeline.tracks[trackIndex].clips[clipIndex])
                return
            }
        }
    }

    // MARK: - Marker operations

    public func addMarker(_ marker: Marker) {
        timeline.markers.append(marker)
        timeline.markers.sort { $0.time < $1.time }
    }

    public func removeMarker(id: UUID) {
        timeline.markers.removeAll { $0.id == id }
    }

    // MARK: - Snapshot (for undo/redo)

    public func snapshot() -> Timeline {
        timeline
    }

    public func restore(_ snapshot: Timeline) {
        self.timeline = snapshot
    }
}
