import Foundation

/// Single source of truth for timeline data.
/// Commands mutate this directly. SwiftUI observes it via @Observable.
/// This is the authoritative timeline — ProjectStore reads from here, not its own copy.
@MainActor @Observable
public final class TimelineState {
    public var timeline: Timeline
    public var broadcastOverlay: BroadcastOverlayConfig?
    public var shortFormConfig: ShortFormConfig?
    public var captionStyle: CaptionStyler.CaptionStyle = .standard

    public init(timeline: Timeline = Timeline(), broadcastOverlay: BroadcastOverlayConfig? = nil, shortFormConfig: ShortFormConfig? = nil) {
        self.timeline = timeline
        self.broadcastOverlay = broadcastOverlay
        self.shortFormConfig = shortFormConfig
    }
}
