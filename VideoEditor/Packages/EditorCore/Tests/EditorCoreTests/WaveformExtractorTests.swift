import Testing
import Foundation
@testable import EditorCore

@Suite("Waveform Extractor Tests")
struct WaveformExtractorTests {

    @Test("WaveformExtractor returns normalized peaks for PCM audio")
    func extractsWaveformFromPCMFile() async throws {
        let fixtureURL = try makePCMFixture(named: "waveform-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let waveform = await WaveformExtractor().extract(from: fixtureURL, sampleCount: 32)

        #expect(waveform != nil)
        #expect(waveform?.count == 32)
        #expect((waveform?.max() ?? 0) > 0.4)
    }

    private func makePCMFixture(named fileName: String) throws -> URL {
        let sampleRate = 44_100
        let durationSeconds = 1.0
        let frameCount = Int(Double(sampleRate) * durationSeconds)
        let amplitude = 0.7
        let frequency = 440.0

        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)
        for sampleIndex in 0..<frameCount {
            let phase = 2 * Double.pi * frequency * Double(sampleIndex) / Double(sampleRate)
            let sample = Int16((sin(phase) * amplitude) * Double(Int16.max))
            var littleEndian = sample.littleEndian
            pcm.append(Data(bytes: &littleEndian, count: MemoryLayout<Int16>.size))
        }

        let wav = makeWaveFile(fromPCMData: pcm, sampleRate: sampleRate, channelCount: 1, bitsPerSample: 16)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try wav.write(to: url)
        return url
    }

    private func makeWaveFile(
        fromPCMData pcmData: Data,
        sampleRate: Int,
        channelCount: Int,
        bitsPerSample: Int
    ) -> Data {
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        let riffChunkSize = 36 + pcmData.count

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(riffChunkSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channelCount).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitsPerSample).littleEndianData)

        data.append("data".data(using: .ascii)!)
        data.append(UInt32(pcmData.count).littleEndianData)
        data.append(pcmData)
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
