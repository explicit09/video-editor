import Foundation

/// Observable state for the timeline UI. Separate from the data model.
@MainActor
public final class TimelineViewState: ObservableObject, Sendable {
    @Published public var playheadPosition: TimeInterval = 0
    @Published public var zoom: Double = 100              // pixels per second
    @Published public var scrollOffset: Double = 0
    @Published public var selectedClipIDs: Set<UUID> = []
    @Published public var selectedTrackID: UUID?
    @Published public var isPlaying: Bool = false

    // Snap
    @Published public var snapEnabled: Bool = true
    public let snapThresholdPixels: Double = 8

    public init() {}

    // MARK: - Zoom

    public static let zoomRange: ClosedRange<Double> = 10...500

    public func zoomIn() {
        zoom = min(zoom * 1.3, Self.zoomRange.upperBound)
    }

    public func zoomOut() {
        zoom = max(zoom / 1.3, Self.zoomRange.lowerBound)
    }

    // MARK: - Conversions

    public func timeToX(_ time: TimeInterval) -> Double {
        time * zoom - scrollOffset
    }

    public func xToTime(_ x: Double) -> TimeInterval {
        max(0, (x + scrollOffset) / zoom)
    }

    public func durationToWidth(_ duration: TimeInterval) -> Double {
        duration * zoom
    }

    // MARK: - Selection

    public func toggleSelection(_ clipID: UUID, extend: Bool) {
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

    public func clearSelection() {
        selectedClipIDs.removeAll()
    }
}
