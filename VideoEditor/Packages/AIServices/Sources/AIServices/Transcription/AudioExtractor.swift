import Foundation
import AVFoundation

/// Extracts audio track from video files for transcription.
/// Outputs a lightweight m4a file instead of uploading multi-GB video.
public struct AudioExtractor: Sendable {

    public init() {}

    /// Extract audio from a video/audio file to a temporary m4a file.
    /// If the input is already audio-only, copies it as-is.
    public func extractAudio(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        // Check if there's an audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioExtractorError.noAudioTrack
        }

        // Create temp output file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription_\(UUID().uuidString).m4a")

        // Use AVAssetExportSession for fast audio extraction
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioExtractorError.exportSessionFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            let msg = session.error?.localizedDescription ?? "unknown"
            throw AudioExtractorError.exportFailed(msg)
        }

        return outputURL
    }

    /// Clean up a temporary audio file after transcription.
    public func cleanup(tempURL: URL) {
        try? FileManager.default.removeItem(at: tempURL)
    }
}

public enum AudioExtractorError: Error, LocalizedError {
    case noAudioTrack
    case exportSessionFailed
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: "No audio track found in media"
        case .exportSessionFailed: "Could not create audio export session"
        case .exportFailed(let msg): "Audio extraction failed: \(msg)"
        }
    }
}
