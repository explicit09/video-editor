import Testing
import Foundation
import AVFoundation
@testable import EditorCore

@Suite("Playback Engine Tests")
struct PlaybackEngineTests {

    @MainActor
    @Test("Seek clamps negative times to zero")
    func seekClampsNegativeTimes() {
        let engine = PlaybackEngine()

        engine.seek(to: -5)

        #expect(engine.currentTime == 0)
    }

    @MainActor
    @Test("Seek clamps times beyond duration")
    func seekClampsPastDuration() {
        let engine = PlaybackEngine()
        engine.duration = 3

        engine.seek(to: 9)

        #expect(engine.currentTime == 3)
    }

    @MainActor
    @Test("Transport controls only start playback when a current item exists")
    func transportControlsRespectCurrentItem() {
        let engine = PlaybackEngine()

        engine.play()
        #expect(engine.isPlaying == false)

        engine.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))

        engine.togglePlayPause()
        #expect(engine.isPlaying == true)

        engine.togglePlayPause()
        #expect(engine.isPlaying == false)
    }
}
