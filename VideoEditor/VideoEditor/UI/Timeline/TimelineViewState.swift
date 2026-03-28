import Foundation
import SwiftUI
import EditorCore

/// Observable UI state for the timeline panel.
@MainActor @Observable
final class TimelineViewState {
    var playheadPosition: TimeInterval = 0
    var zoom: Double = 100              // pixels per second
    var selectedClipIDs: Set<UUID> = []
    var selectedTrackID: UUID?
    var isPlaying: Bool = false
    var snapEnabled: Bool = true
    var rippleEnabled: Bool = false
    var linkedSelectionEnabled: Bool = true
    var visibleWidth: Double = 800
    let snapThresholdPixels: Double = 8

    // MARK: - Zoom

    static let zoomRange: ClosedRange<Double> = 0.05...2400
    static let zoomPresets: [Double] = [12.5, 25, 50, 100, 200, 400, 800, 1600]
    static let detailZoom: Double = 400

    func setZoom(_ value: Double) {
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    func zoomIn() {
        setZoom(nextZoom(from: zoom, direction: .in))
    }

    func zoomOut() {
        setZoom(nextZoom(from: zoom, direction: .out))
    }

    /// Zoom to fit the entire timeline in the current visible width.
    func zoomToFit(duration: TimeInterval) {
        zoomToRange(TimeRange(start: 0, duration: max(duration, 0.1)))
    }

    func zoomToRange(_ range: TimeRange) {
        guard range.duration > 0, visibleWidth > 0 else { return }
        let usableWidth = max(visibleWidth - 120, 120)
        setZoom(usableWidth / range.duration)
    }

    func zoomToDetail() {
        setZoom(Self.detailZoom)
    }

    // MARK: - Conversions

    func durationToWidth(_ duration: TimeInterval) -> Double {
        duration * zoom
    }

    func xToTime(_ x: Double) -> TimeInterval {
        max(0, x / zoom)
    }

    // MARK: - Selection

    func selectTrack(_ trackID: UUID) {
        selectedTrackID = trackID
        selectedClipIDs.removeAll()
    }

    func selectClip(_ clipID: UUID, in trackID: UUID) {
        selectedTrackID = trackID
        selectedClipIDs = [clipID]
    }

    func toggleSelection(_ clipID: UUID, in trackID: UUID, extend: Bool) {
        selectedTrackID = trackID
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
        selectedTrackID = nil
    }

    private enum ZoomDirection {
        case `in`
        case out
    }

    private func nextZoom(from current: Double, direction: ZoomDirection) -> Double {
        switch direction {
        case .in:
            if let preset = Self.zoomPresets.first(where: { $0 > current * 1.05 }) {
                return preset
            }
            return min(current * 1.5, Self.zoomRange.upperBound)
        case .out:
            if let preset = Self.zoomPresets.last(where: { $0 < current / 1.05 }) {
                return preset
            }
            return max(current / 1.5, Self.zoomRange.lowerBound)
        }
    }
}
