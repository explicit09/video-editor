import Foundation
import AVFoundation

/// Imports media files, extracts metadata, and generates thumbnails.
public struct MediaImporter: Sendable {

    public init() {}

    /// Import a media file from a source URL. Returns a MediaAsset with metadata populated.
    public func importFile(from sourceURL: URL) async throws -> MediaAsset {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        let type = mediaType(for: sourceURL)

        var width: Int?
        var height: Int?
        var codec: String?

        if type == .video || type == .image {
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await videoTrack.load(.naturalSize)
                width = Int(size.width)
                height = Int(size.height)
                let descriptions = try await videoTrack.load(.formatDescriptions)
                if let desc = descriptions.first {
                    codec = CMFormatDescriptionGetMediaSubType(desc).fourCharString
                }
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0

        return MediaAsset(
            name: sourceURL.deletingPathExtension().lastPathComponent,
            sourceURL: sourceURL,
            type: type,
            duration: duration,
            width: width,
            height: height,
            codec: codec,
            fileSize: fileSize
        )
    }

    /// Generate a thumbnail image at a specific time.
    public func generateThumbnail(
        for sourceURL: URL,
        at time: TimeInterval = 0,
        maxSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> CGImage {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSize
        generator.appliesPreferredTrackTransform = true

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: cmTime)
        return image
    }

    /// Copy source file into the project bundle media/ directory.
    public func copyToBundle(
        sourceURL: URL,
        bundleMediaDir: URL,
        assetID: UUID
    ) throws -> URL {
        let ext = sourceURL.pathExtension
        let destURL = bundleMediaDir.appendingPathComponent("\(assetID.uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    // MARK: - Private

    private func mediaType(for url: URL) -> MediaType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return .video
        case "mp3", "wav", "aac", "m4a", "flac", "aiff":
            return .audio
        case "jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif":
            return .image
        default:
            return .video
        }
    }
}

// MARK: - FourCC helper

extension FourCharCode {
    var fourCharString: String {
        let bytes = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
