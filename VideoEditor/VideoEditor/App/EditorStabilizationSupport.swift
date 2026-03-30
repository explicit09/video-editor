import Foundation
import EditorCore

enum WaveformLoadState: Equatable {
    case loading
    case ready([Float])
    case noAudio
    case failed
}

enum WaveformLoadStateResolver {
    static func resolve(
        for asset: MediaAsset,
        hasAudioTrack: Bool?,
        extractionInFlight: Bool
    ) -> WaveformLoadState? {
        switch asset.type {
        case .image:
            return nil
        case .audio:
            if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
                return .ready(profile)
            }
            return extractionInFlight ? .loading : .failed
        case .video:
            if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
                return .ready(profile)
            }
            if let hasAudioTrack {
                return hasAudioTrack ? (extractionInFlight ? .loading : .failed) : .noAudio
            }
            return .loading
        }
    }
}

struct TimelineTrackDisplayState: Equatable {
    var trackHeights: [UUID: Double]
    var collapsedTrackIDs: Set<UUID>
}

enum TimelineTrackDisplayStatePruner {
    static func prune(
        _ state: TimelineTrackDisplayState,
        validTrackIDs: Set<UUID>
    ) -> TimelineTrackDisplayState {
        TimelineTrackDisplayState(
            trackHeights: state.trackHeights.filter { validTrackIDs.contains($0.key) },
            collapsedTrackIDs: state.collapsedTrackIDs.intersection(validTrackIDs)
        )
    }
}

enum EditorShortcutGuard {
    static func shouldHandleGlobalShortcut(isTextInputFocused: Bool) -> Bool {
        !isTextInputFocused
    }
}
