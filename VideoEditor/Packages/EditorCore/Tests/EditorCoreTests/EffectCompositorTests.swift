import Testing
import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
@testable import EditorCore

@Suite("Effect Compositor Tests")
struct EffectCompositorTests {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    private func makeSolidImage(color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func rgbaAt(_ point: CGPoint, in image: CIImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let bounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        ciContext.render(
            image.cropped(to: bounds),
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    @Test("Overlay layers are processed in stable track order")
    func orderedOverlayLayersSortsByTrackOrder() {
        let instruction = OverlayInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            layers: [
                OverlayLayer(trackID: 3, trackOrder: 2),
                OverlayLayer(trackID: 1, trackOrder: 0),
                OverlayLayer(trackID: 2, trackOrder: 1),
            ]
        )

        #expect(EffectCompositor.orderedOverlayLayers(for: instruction).map(\.trackOrder) == [0, 1, 2])
    }

    @Test("PiP presentation applies rounded masking to overlay layers")
    func applyOverlayPresentationMasksRoundedPiPLayers() {
        let image = makeSolidImage(color: .red, size: CGSize(width: 10, height: 10))
        let presentation = OverlayPresentation(
            mode: .pip,
            border: .hidden,
            shadow: .none,
            cornerRadius: 4,
            maskShape: .roundedRect,
            snapsToSafeMargins: true,
            entranceAnimation: .none,
            exitAnimation: .none
        )

        let rendered = EffectCompositor.applyOverlayPresentation(presentation, to: image, renderSize: CGSize(width: 10, height: 10))

        let corner = rgbaAt(CGPoint(x: 0, y: 0), in: rendered)
        let center = rgbaAt(CGPoint(x: 5, y: 5), in: rendered)

        #expect(corner.a == 0)
        #expect(center.a == 255)
    }
}
