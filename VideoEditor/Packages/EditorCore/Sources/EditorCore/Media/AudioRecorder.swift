import Foundation
import AVFoundation

/// Records audio from the system microphone for voiceover.
/// Saves to a temporary file that can be imported into the project.
@MainActor @Observable
public final class AudioRecorder {
    public private(set) var isRecording = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var peakLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var timer: Timer?

    public init() {}

    /// Start recording to a temporary file.
    /// Returns the URL where the recording will be saved.
    public func startRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceover_\(UUID().uuidString).m4a")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Create output file
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? file.write(from: buffer)

            // Update peak level for UI
            let channelData = buffer.floatChannelData?[0]
            let frameLength = UInt(buffer.frameLength)
            if let data = channelData {
                var peak: Float = 0
                for i in 0..<Int(frameLength) {
                    let abs = Swift.abs(data[i])
                    if abs > peak { peak = abs }
                }
                Task { @MainActor [weak self] in
                    self?.peakLevel = peak
                }
            }
        }

        try engine.start()

        self.audioEngine = engine
        self.outputFile = file
        self.outputURL = url
        self.isRecording = true
        self.currentTime = 0

        // Update time display
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime += 0.1
            }
        }

        return url
    }

    /// Stop recording and return the file URL.
    public func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        peakLevel = 0

        return outputURL
    }

    /// Cancel recording and delete the file.
    public func cancelRecording() {
        let url = stopRecording()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
