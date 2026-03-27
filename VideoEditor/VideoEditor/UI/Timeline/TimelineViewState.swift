import Foundation

/// Observable UI state for the timeline panel. Not editor logic — lives in app target.
@MainActor
final class TimelineViewState: ObservableObject {
    @Published var playheadPosition: TimeInterval = 0
    @Published var zoom: Double = 100              // pixels per second
    @Published var scrollOffset: Double = 0
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var selectedTrackID: UUID?
    @Published var isPlaying: Bool = false
    @Published var snapEnabled: Bool = true
    let snapThresholdPixels: Double = 8

    // MARK: - Zoom

    static let zoomRange: ClosedRange<Double> = 10...500

    func zoomIn() {
        zoom = min(zoom * 1.3, Self.zoomRange.upperBound)
    }

    func zoomOut() {
        zoom = max(zoom / 1.3, Self.zoomRange.lowerBound)
    }

    // MARK: - Conversions

    func timeToX(_ time: TimeInterval) -> Double {
        time * zoom - scrollOffset
    }

    func xToTime(_ x: Double) -> TimeInterval {
        max(0, (x + scrollOffset) / zoom)
    }

    func durationToWidth(_ duration: TimeInterval) -> Double {
        duration * zoom
    }

    // MARK: - Selection

    func toggleSelection(_ clipID: UUID, extend: Bool) {
        if extend {
            if selectedClipIDs.contains(clipID) {
                selectedClipIDs.remove(clipID)
            } else {
                selectedClipIDs.insert(clipID)
            }
        } else {
            selectedClipIDs = [clipID]
        }
    }

    func clearSelection() {
        selectedClipIDs.removeAll()
    }
}
