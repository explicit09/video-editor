import Foundation

// MARK: - Overlay Geometry Helpers

/// Pure geometry math for positioning and scaling overlay clips on a canvas.
/// Used by both the compositor (rendering) and the monitor controls (interaction).
public enum OverlayGeometry {

    /// Safe margin in points from canvas edges for PiP presets.
    public static let safeMargin: CGFloat = 48

    /// Minimum allowed scale factor for overlay clips.
    public static let minimumScale: Double = 0.05

    /// Default PiP scale factor (fraction of canvas).
    public static let defaultPiPScale: Double = 0.35

    // MARK: - Preset Frames

    /// Returns a pixel-space CGRect for a PiP preset position within the given canvas.
    public static func presetFrame(_ preset: OverlayPiPPreset, canvasSize: CGSize) -> CGRect {
        let scale = defaultPiPScale
        let width = canvasSize.width * scale
        let height = canvasSize.height * scale

        let x: CGFloat
        let y: CGFloat

        switch preset {
        case .topLeft:
            x = safeMargin
            y = safeMargin
        case .topRight:
            x = canvasSize.width - safeMargin - width
            y = safeMargin
        case .bottomLeft:
            x = safeMargin
            y = canvasSize.height - safeMargin - height
        case .bottomRight:
            x = canvasSize.width - safeMargin - width
            y = canvasSize.height - safeMargin - height
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Transform Manipulation

    /// Returns a new transform with position shifted by a pixel delta, normalized to canvas size.
    /// Position uses normalized coordinates where 1.0 = full canvas width/height.
    public static func transformByTranslating(
        _ transform: Transform2D,
        delta: CGSize,
        canvasSize: CGSize
    ) -> Transform2D {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return transform }

        let normalizedDX = Double(delta.width / canvasSize.width)
        let normalizedDY = Double(delta.height / canvasSize.height)

        return Transform2D(
            positionX: transform.positionX + normalizedDX,
            positionY: transform.positionY + normalizedDY,
            scaleX: transform.scaleX,
            scaleY: transform.scaleY,
            rotation: transform.rotation,
            anchorX: transform.anchorX,
            anchorY: transform.anchorY
        )
    }

    /// Returns a new transform with scale adjusted by a pixel delta.
    /// Maintains aspect ratio by using the larger axis delta.
    public static func transformByScaling(
        _ transform: Transform2D,
        anchor: CGPoint,
        delta: CGSize
    ) -> Transform2D {
        // Use diagonal distance for uniform scaling
        let scaleDelta = Double((delta.width + delta.height) / 2) * 0.005
        let newScaleX = max(transform.scaleX + scaleDelta, minimumScale)
        let newScaleY = max(transform.scaleY + scaleDelta, minimumScale)

        return Transform2D(
            positionX: transform.positionX,
            positionY: transform.positionY,
            scaleX: newScaleX,
            scaleY: newScaleY,
            rotation: transform.rotation,
            anchorX: transform.anchorX,
            anchorY: transform.anchorY
        )
    }

    // MARK: - Display Frame

    /// Converts a clip's normalized transform into a pixel-space frame on the canvas.
    /// Transform convention: positionX/Y are normalized offsets from center (-0.5 to 0.5 range).
    /// scaleX/Y are the fraction of canvas the clip occupies.
    public static func displayFrame(for clip: Clip, canvasSize: CGSize) -> CGRect {
        let t = clip.transform
        let width = canvasSize.width * CGFloat(t.scaleX)
        let height = canvasSize.height * CGFloat(t.scaleY)

        // Position is normalized offset from canvas center
        let centerX = canvasSize.width / 2 + canvasSize.width * CGFloat(t.positionX)
        let centerY = canvasSize.height / 2 - canvasSize.height * CGFloat(t.positionY)

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Snapping

    /// Snap threshold in pixels. Edges within this distance of a guide snap to it.
    public static let snapThreshold: CGFloat = 8

    /// Result of snapping a transform, including optional guide positions for UI rendering.
    public struct OverlaySnapResult: Equatable, Sendable {
        public let transform: Transform2D
        public let verticalGuide: CGFloat?
        public let horizontalGuide: CGFloat?
    }

    /// Snaps the overlay edges to safe margins and canvas center when nearby.
    /// Returns the adjusted transform plus guide positions for drawing snap lines.
    public static func snapped(
        _ transform: Transform2D,
        canvasSize: CGSize,
        snapsToSafeMargins: Bool
    ) -> OverlaySnapResult {
        guard snapsToSafeMargins, canvasSize.width > 0, canvasSize.height > 0 else {
            return OverlaySnapResult(transform: transform, verticalGuide: nil, horizontalGuide: nil)
        }

        // Compute the overlay rect in pixel space
        let width = canvasSize.width * CGFloat(transform.scaleX)
        let height = canvasSize.height * CGFloat(transform.scaleY)
        let centerX = canvasSize.width / 2 + canvasSize.width * CGFloat(transform.positionX)
        let centerY = canvasSize.height / 2 - canvasSize.height * CGFloat(transform.positionY)

        let left = centerX - width / 2
        let right = centerX + width / 2
        let top = centerY - height / 2
        let bottom = centerY + height / 2

        // Guide lines we can snap to
        let canvasCenterX = canvasSize.width / 2
        let canvasCenterY = canvasSize.height / 2
        let safeLeft = safeMargin
        let safeRight = canvasSize.width - safeMargin
        let safeTop = safeMargin
        let safeBottom = canvasSize.height - safeMargin

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var vGuide: CGFloat?
        var hGuide: CGFloat?

        // Horizontal snapping (X axis): check left edge, right edge, center
        let hCandidates: [(edge: CGFloat, guide: CGFloat)] = [
            (left, safeLeft),
            (right, safeRight),
            (centerX, canvasCenterX),
        ]
        if let best = hCandidates.min(by: { abs($0.edge - $0.guide) < abs($1.edge - $1.guide) }),
           abs(best.edge - best.guide) <= snapThreshold {
            dx = best.guide - best.edge
            vGuide = best.guide
        }

        // Vertical snapping (Y axis): check top edge, bottom edge, center
        let vCandidates: [(edge: CGFloat, guide: CGFloat)] = [
            (top, safeTop),
            (bottom, safeBottom),
            (centerY, canvasCenterY),
        ]
        if let best = vCandidates.min(by: { abs($0.edge - $0.guide) < abs($1.edge - $1.guide) }),
           abs(best.edge - best.guide) <= snapThreshold {
            dy = best.guide - best.edge
            hGuide = best.guide
        }

        guard dx != 0 || dy != 0 else {
            return OverlaySnapResult(transform: transform, verticalGuide: nil, horizontalGuide: nil)
        }

        // Convert pixel deltas back to normalized coordinates
        let snappedX = transform.positionX + Double(dx / canvasSize.width)
        // Y is inverted: pixel-down = negative in normalized coords
        let snappedY = transform.positionY - Double(dy / canvasSize.height)

        let snappedTransform = Transform2D(
            positionX: snappedX,
            positionY: snappedY,
            scaleX: transform.scaleX,
            scaleY: transform.scaleY,
            rotation: transform.rotation,
            anchorX: transform.anchorX,
            anchorY: transform.anchorY
        )

        return OverlaySnapResult(transform: snappedTransform, verticalGuide: vGuide, horizontalGuide: hGuide)
    }
}
