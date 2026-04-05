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
    var armedTrackID: UUID?
    var dragTargetTrackID: UUID?
    var isPlaying: Bool = false
    var snapEnabled: Bool = true
    var rippleEnabled: Bool = false
    var linkedSelectionEnabled: Bool = true
    var autoFollowPlayhead: Bool = false
    var lastSelectedClipID: UUID?
    var placementMode: PlacementMode = .overwrite
    var trackLayoutState = TrackLayoutState()

    enum PlacementMode: String, CaseIterable {
        case insert = "Insert"
        case overwrite = "Overwrite"
        case replace = "Replace"

        var icon: String {
            switch self {
            case .insert: "arrow.right.to.line"
            case .overwrite: "square.on.square"
            case .replace: "arrow.left.arrow.right"
            }
        }
    }
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
        lastSelectedClipID = nil
    }

    func armTrack(_ trackID: UUID) {
        armedTrackID = trackID
    }

    func toggleArmedTrack(_ trackID: UUID) {
        armedTrackID = armedTrackID == trackID ? nil : trackID
    }

    func clearArmedTrack() {
        armedTrackID = nil
    }

    func updateDragTargetTrack(_ trackID: UUID?) {
        dragTargetTrackID = trackID
    }

    var effectiveTargetTrackID: UUID? {
        dragTargetTrackID ?? armedTrackID
    }

    func selectClip(_ clipID: UUID, in trackID: UUID) {
        selectedTrackID = trackID
        selectedClipIDs = [clipID]
        lastSelectedClipID = clipID
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
        lastSelectedClipID = clipID
    }

    /// Select all clips on a track between the anchor and target clip (by timeline position).
    func rangeSelect(to targetClipID: UUID, in trackClips: [Clip]) {
        guard let anchorID = lastSelectedClipID else {
            selectedClipIDs = [targetClipID]
            lastSelectedClipID = targetClipID
            return
        }
        guard let anchorClip = trackClips.first(where: { $0.id == anchorID }),
              let targetClip = trackClips.first(where: { $0.id == targetClipID }) else {
            selectedClipIDs.insert(targetClipID)
            return
        }
        let minStart = min(anchorClip.timelineRange.start, targetClip.timelineRange.start)
        let maxEnd = max(anchorClip.timelineRange.end, targetClip.timelineRange.end)
        let inRange = trackClips.filter { $0.timelineRange.start >= minStart && $0.timelineRange.end <= maxEnd }
        for clip in inRange {
            selectedClipIDs.insert(clip.id)
        }
        lastSelectedClipID = targetClipID
    }

    func clearSelection() {
        selectedClipIDs.removeAll()
        selectedTrackID = nil
        lastSelectedClipID = nil
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
