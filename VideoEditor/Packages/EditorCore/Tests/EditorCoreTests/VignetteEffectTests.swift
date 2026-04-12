import Testing
@testable import EditorCore

@Suite("Vignette Effect Tests")
struct VignetteEffectTests {
    @Test("Vignette EffectInstance factory")
    func vignetteFactory() {
        let effect = EffectInstance.vignette(intensity: 0.6, feather: 0.8)
        #expect(effect.type == EffectInstance.typeVignette)
        #expect(effect.parameters["intensity"] == 0.6)
        #expect(effect.parameters["feather"] == 0.8)
    }

    @Test("Vignette with defaults")
    func vignetteDefaults() {
        let effect = EffectInstance.vignette()
        #expect(effect.parameters["intensity"] == 0.5)
        #expect(effect.parameters["feather"] == 0.7)
    }
}
