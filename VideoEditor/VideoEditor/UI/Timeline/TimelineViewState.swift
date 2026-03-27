import Foundation
import SwiftUI

/// Observable UI state for the timeline panel.
@MainActor @Observable
final class TimelineViewState {
    var playheadPosition: TimeInterval = 0
    var zoom: Double = 100              // pixels per second
    var selectedClipIDs: Set<UUID> = []
    var selectedTrackID: UUID?
    var isPlaying: Bool = false
    var snapEnabled: Bool = true
    let snapThresholdPixels: Double = 8

    // MARK: - Zoom

    static let zoomRange: ClosedRange<Double> = 5...1000

    func zoomIn() {
        zoom = min(zoom * 1.3, Self.zoomRange.upperBound)
    }

    func zoomOut() {
        zoom = max(zoom / 1.3, Self.zoomRange.lowerBound)
    }

    /// Zoom to fit the entire timeline in the given visible width.
    func zoomToFit(duration: TimeInterval, visibleWidth: Double) {
        guard duration > 0, visibleWidth > 0 else { return }
        let padding: Double = 40 // leave some padding on right
        zoom = max((visibleWidth - padding) / duration, Self.zoomRange.lowerBound)
    }

    // MARK: - Conversions

    func durationToWidth(_ duration: TimeInterval) -> Double {
        duration * zoom
    }

    func xToTime(_ x: Double) -> TimeInterval {
        max(0, x / zoom)
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
