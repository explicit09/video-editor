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
}
