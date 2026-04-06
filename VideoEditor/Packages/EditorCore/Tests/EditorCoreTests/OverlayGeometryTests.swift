import Testing
import Foundation
@testable import EditorCore

@Suite("Overlay Geometry Tests")
struct OverlayGeometryTests {

    @Test("PiP preset frame fits inside safe margins")
    func pipPresetFrameFitsInsideSafeMargins() {
        let canvas = CGSize(width: 1920, height: 1080)
        for preset in [OverlayPiPPreset.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let frame = OverlayGeometry.presetFrame(preset, canvasSize: canvas)
            #expect(frame.minX >= OverlayGeometry.safeMargin, "preset \(preset) minX out of safe margin")
            #expect(frame.minY >= OverlayGeometry.safeMargin, "preset \(preset) minY out of safe margin")
            #expect(frame.maxX <= canvas.width - OverlayGeometry.safeMargin, "preset \(preset) maxX out of safe margin")
            #expect(frame.maxY <= canvas.height - OverlayGeometry.safeMargin, "preset \(preset) maxY out of safe margin")
        }
    }

    @Test("Preset frames have expected quadrant positions")
    func presetFramesInCorrectQuadrants() {
        let canvas = CGSize(width: 1920, height: 1080)
        let midX = canvas.width / 2
        let midY = canvas.height / 2

        let topLeft = OverlayGeometry.presetFrame(.topLeft, canvasSize: canvas)
        #expect(topLeft.midX < midX)
        #expect(topLeft.midY < midY)

        let topRight = OverlayGeometry.presetFrame(.topRight, canvasSize: canvas)
        #expect(topRight.midX > midX)
        #expect(topRight.midY < midY)

        let bottomLeft = OverlayGeometry.presetFrame(.bottomLeft, canvasSize: canvas)
        #expect(bottomLeft.midX < midX)
        #expect(bottomLeft.midY > midY)

        let bottomRight = OverlayGeometry.presetFrame(.bottomRight, canvasSize: canvas)
        #expect(bottomRight.midX > midX)
        #expect(bottomRight.midY > midY)
    }

    @Test("Dragging overlay produces updated transform")
    func draggingProducesUpdatedTransform() {
        let initial = Transform2D.identity
        let canvas = CGSize(width: 1920, height: 1080)
        let updated = OverlayGeometry.transformByTranslating(initial, delta: CGSize(width: 120, height: -60), canvasSize: canvas)
        #expect(updated.positionX > initial.positionX)
        #expect(updated.positionY < initial.positionY)
    }

    @Test("Translation delta is normalized to canvas")
    func translationNormalizesToCanvas() {
        let initial = Transform2D(positionX: 0, positionY: 0)
        let canvas = CGSize(width: 1920, height: 1080)
        let updated = OverlayGeometry.transformByTranslating(initial, delta: CGSize(width: 1920, height: 1080), canvasSize: canvas)
        // Moving the full canvas width should produce +1.0 normalized X
        #expect(abs(updated.positionX - 1.0) < 0.001)
        #expect(abs(updated.positionY - 1.0) < 0.001)
    }

    @Test("Scaling changes scaleX and scaleY proportionally")
    func scalingChangesScale() {
        let initial = Transform2D(positionX: 0, positionY: 0, scaleX: 0.35, scaleY: 0.35)
        let updated = OverlayGeometry.transformByScaling(initial, anchor: .zero, delta: CGSize(width: 50, height: 50))
        #expect(updated.scaleX > initial.scaleX)
        #expect(updated.scaleY > initial.scaleY)
    }

    @Test("Scale has a minimum floor")
    func scaleHasMinimumFloor() {
        let initial = Transform2D(positionX: 0, positionY: 0, scaleX: 0.1, scaleY: 0.1)
        let updated = OverlayGeometry.transformByScaling(initial, anchor: .zero, delta: CGSize(width: -5000, height: -5000))
        #expect(updated.scaleX >= OverlayGeometry.minimumScale)
        #expect(updated.scaleY >= OverlayGeometry.minimumScale)
    }

    // MARK: - Snapping Tests

    @Test("Translation snaps to safe margin when enabled")
    func translationSnapsToSafeMarginWhenEnabled() {
        let canvas = CGSize(width: 1920, height: 1080)
        // Place overlay so right edge is ~4px from right safe margin (1872).
        // right edge = (960 + 1920*posX) + (1920*0.35)/2 = 960 + 1920*posX + 336
        // Want right edge = 1876 → posX = (1876 - 336 - 960) / 1920 = 0.302
        let transform = Transform2D(positionX: 0.302, positionY: 0, scaleX: 0.35, scaleY: 0.35)
        let result = OverlayGeometry.snapped(transform, canvasSize: canvas, snapsToSafeMargins: true)
        // Should snap since right edge is within threshold of right safe margin
        #expect(result.transform.positionX != transform.positionX)
        #expect(result.verticalGuide == canvas.width - OverlayGeometry.safeMargin)
    }

    @Test("Snapping disabled returns original transform")
    func snappingDisabledReturnsOriginal() {
        let transform = Transform2D(positionX: 0.46, positionY: -0.46, scaleX: 0.35, scaleY: 0.35)
        let canvas = CGSize(width: 1920, height: 1080)
        let result = OverlayGeometry.snapped(transform, canvasSize: canvas, snapsToSafeMargins: false)
        #expect(result.transform == transform)
        #expect(result.verticalGuide == nil)
        #expect(result.horizontalGuide == nil)
    }

    @Test("Snapping to center when overlay is near center")
    func snapsToCenter() {
        // Position near center (small offset)
        let transform = Transform2D(positionX: 0.002, positionY: -0.003, scaleX: 0.35, scaleY: 0.35)
        let canvas = CGSize(width: 1920, height: 1080)
        let result = OverlayGeometry.snapped(transform, canvasSize: canvas, snapsToSafeMargins: true)
        // Center of overlay should snap to canvas center
        #expect(result.verticalGuide == canvas.width / 2)
        #expect(result.horizontalGuide == canvas.height / 2)
    }

    @Test("No snap when far from any guide")
    func noSnapWhenFarFromGuides() {
        // Position clearly between guides
        let transform = Transform2D(positionX: 0.2, positionY: -0.2, scaleX: 0.2, scaleY: 0.2)
        let canvas = CGSize(width: 1920, height: 1080)
        let result = OverlayGeometry.snapped(transform, canvasSize: canvas, snapsToSafeMargins: true)
        #expect(result.transform == transform)
        #expect(result.verticalGuide == nil)
        #expect(result.horizontalGuide == nil)
    }

    @Test("Snap result provides guide positions for UI")
    func snapResultProvidesGuides() {
        let canvas = CGSize(width: 1920, height: 1080)
        // Right edge near safe margin — same as the snap-to-safe-margin test
        let transform = Transform2D(positionX: 0.302, positionY: 0, scaleX: 0.35, scaleY: 0.35)
        let result = OverlayGeometry.snapped(transform, canvasSize: canvas, snapsToSafeMargins: true)
        #expect(result.verticalGuide != nil, "Guide position should be provided when snapping occurs")
    }

    @Test("Display frame for pip clip uses transform position and scale")
    func displayFrameUsesTransform() {
        var clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            transform: Transform2D(positionX: 0.45, positionY: -0.45, scaleX: 0.35, scaleY: 0.35)
        )
        clip.overlayPresentation = OverlayPresentation(mode: .pip)
        let canvas = CGSize(width: 1920, height: 1080)
        let frame = OverlayGeometry.displayFrame(for: clip, canvasSize: canvas)

        // Frame should be in the bottom-right area (positive X = right, negative Y = bottom in normalized)
        #expect(frame.width > 0)
        #expect(frame.height > 0)
        #expect(frame.midX > canvas.width / 2)
    }
}
