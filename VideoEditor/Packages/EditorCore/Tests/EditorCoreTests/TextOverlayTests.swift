import Testing
import Foundation
@testable import EditorCore

@Suite("TextOverlay")
struct TextOverlayTests {

    @Test("Default values are set correctly")
    func defaultValues() {
        let overlay = TextOverlay(text: "Hello World")

        #expect(overlay.text == "Hello World")
        #expect(overlay.startTime == 0)
        #expect(overlay.duration == 3)
        #expect(overlay.positionX == 0.5)
        #expect(overlay.positionY == 0.8)
        #expect(overlay.fontSize == 48)
        #expect(overlay.colorHex == "#FFFFFF")
        #expect(overlay.backgroundColorHex == nil)
        #expect(overlay.animation == .fadeIn)
        #expect(overlay.animationDurationMS == 100)
    }

    @Test("Custom values are stored")
    func customValues() {
        let id = UUID()
        let overlay = TextOverlay(
            id: id,
            text: "Lower Third",
            startTime: 2.5,
            duration: 5.0,
            positionX: 0.1,
            positionY: 0.9,
            fontSize: 36,
            colorHex: "#000000",
            backgroundColorHex: "#FFFF00",
            animation: .slideUp,
            animationDurationMS: 250
        )

        #expect(overlay.id == id)
        #expect(overlay.text == "Lower Third")
        #expect(overlay.startTime == 2.5)
        #expect(overlay.duration == 5.0)
        #expect(overlay.positionX == 0.1)
        #expect(overlay.positionY == 0.9)
        #expect(overlay.fontSize == 36)
        #expect(overlay.colorHex == "#000000")
        #expect(overlay.backgroundColorHex == "#FFFF00")
        #expect(overlay.animation == .slideUp)
        #expect(overlay.animationDurationMS == 250)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = TextOverlay(
            text: "Round Trip Test",
            startTime: 1.0,
            duration: 4.0,
            positionX: 0.3,
            positionY: 0.7,
            fontSize: 64,
            colorHex: "#FF0000",
            backgroundColorHex: "#00000080",
            animation: .pop,
            animationDurationMS: 200
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TextOverlay.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.text == original.text)
        #expect(decoded.startTime == original.startTime)
        #expect(decoded.duration == original.duration)
        #expect(decoded.positionX == original.positionX)
        #expect(decoded.positionY == original.positionY)
        #expect(decoded.fontSize == original.fontSize)
        #expect(decoded.colorHex == original.colorHex)
        #expect(decoded.backgroundColorHex == original.backgroundColorHex)
        #expect(decoded.animation == original.animation)
        #expect(decoded.animationDurationMS == original.animationDurationMS)
    }

    @Test("Codable round-trip with nil backgroundColorHex")
    func codableRoundTripNilBackground() throws {
        let original = TextOverlay(text: "No Background", backgroundColorHex: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

        #expect(decoded == original)
        #expect(decoded.backgroundColorHex == nil)
    }

    @Test("All TextAnimation cases are codable")
    func textAnimationCodable() throws {
        let cases: [TextAnimation] = [.none, .fadeIn, .pop, .slideUp]
        for animation in cases {
            let data = try JSONEncoder().encode(animation)
            let decoded = try JSONDecoder().decode(TextAnimation.self, from: data)
            #expect(decoded == animation)
        }
    }

    @Test("Clip textOverlays defaults to empty array")
    func clipTextOverlaysDefault() {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10)
        )
        #expect(clip.textOverlays.isEmpty)
    }

    @Test("Clip stores textOverlays")
    func clipStoresTextOverlays() {
        let overlay = TextOverlay(text: "Callout")
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10),
            textOverlays: [overlay]
        )
        #expect(clip.textOverlays.count == 1)
        #expect(clip.textOverlays[0].text == "Callout")
    }
}
