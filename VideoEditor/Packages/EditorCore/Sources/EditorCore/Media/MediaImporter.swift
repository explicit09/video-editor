import Foundation
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

/// Imports media files, extracts metadata, and generates thumbnails.
public struct MediaImporter: Sendable {
    private static let genericUnreadableReasons: Set<String> = [
        "Cannot Open",
        "The operation could not be completed",
        "The operation couldn’t be completed",
    ]

    public enum ImportError: LocalizedError {
        case unsupportedFileType(URL)
        case unreadableImage(URL)
        case unreadableMedia(URL, String?)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let url):
                return "Unsupported media type: \(url.lastPathComponent)"
            case .unreadableImage(let url):
                return "Could not read image metadata from \(url.lastPathComponent)"
            case .unreadableMedia(let url, let reason):
                if let reason, !reason.isEmpty {
                    return "Could not open media file \(url.lastPathComponent): \(reason)"
                }
                return "Could not open media file \(url.lastPathComponent). The file may be incomplete or corrupted."
            }
        }
    }

    public init() {}

    /// Import a media file from a source URL. Returns a MediaAsset with metadata populated.
    public func importFile(from sourceURL: URL) async throws -> MediaAsset {
        let type = try await mediaType(for: sourceURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0

        var width: Int?
        var height: Int?
        var codec: String?
        var duration: TimeInterval = 0
        var hasAudioTrack = false

        switch type {
        case .image:
            let metadata = try imageMetadata(for: sourceURL)
            width = metadata.width
            height = metadata.height
            // Images never have audio
            hasAudioTrack = false

        case .video, .audio:
            let asset = AVURLAsset(url: sourceURL)
            do {
                duration = try await asset.load(.duration).seconds

                if type == .video,
                   let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let size = try await videoTrack.load(.naturalSize)
                    width = Int(size.width)
                    height = Int(size.height)
                    let descriptions = try await videoTrack.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        codec = CMFormatDescriptionGetMediaSubType(desc).fourCharString
                    }
                } else if type == .audio,
                          let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                    let descriptions = try await audioTrack.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        codec = CMFormatDescriptionGetMediaSubType(desc).fourCharString
                    }
                }

                // Probe audio track using the SAME asset instance (already loaded)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                hasAudioTrack = !audioTracks.isEmpty
            } catch {
                throw ImportError.unreadableMedia(sourceURL, normalizedUnreadableReason(for: error))
            }
        }

        return MediaAsset(
            name: sourceURL.deletingPathExtension().lastPathComponent,
            sourceURL: sourceURL,
            type: type,
            duration: duration,
            width: width,
            height: height,
            codec: codec,
            fileSize: fileSize,
            hasAudioTrack: hasAudioTrack
        )
    }

    /// Generate a thumbnail image at a specific time.
    public func generateThumbnail(
        for sourceURL: URL,
        at time: TimeInterval = 0,
        maxSize: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> CGImage {
        let type = try await mediaType(for: sourceURL)

        if type == .image {
            guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw ImportError.unreadableImage(sourceURL)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(maxSize.width, maxSize.height),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw ImportError.unreadableImage(sourceURL)
            }
            return image
        }

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
        let ext = sourceURL.pathExtension.lowercased()
        let destinationName = ext.isEmpty ? assetID.uuidString : "\(assetID.uuidString).\(ext)"
        let destURL = bundleMediaDir.appendingPathComponent(destinationName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            try streamCopy(from: sourceURL, to: destURL)
        }
        return destURL
    }

    // MARK: - Private

    func mediaType(for url: URL) async throws -> MediaType {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if contentType.conforms(to: .image) {
                return .image
            }
            if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                return .video
            }
            if contentType.conforms(to: .audio) {
                return .audio
            }
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "m2ts", "mts", "3gp":
            return .video
        case "mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "caf", "ogg", "opus":
            return .audio
        case "jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp", "avif":
            return .image
        default:
            let asset = AVURLAsset(url: url)
            if let videoTracks = try? await asset.loadTracks(withMediaType: .video), !videoTracks.isEmpty {
                return .video
            }
            if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), !audioTracks.isEmpty {
                return .audio
            }
            if CGImageSourceCreateWithURL(url as CFURL, nil) != nil {
                return .image
            }
            throw ImportError.unsupportedFileType(url)
        }
    }

    private func imageMetadata(for sourceURL: URL) throws -> (width: Int?, height: Int?) {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw ImportError.unreadableImage(sourceURL)
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        return (width, height)
    }

    private func streamCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let reader = try FileHandle(forReadingFrom: sourceURL)
        let writer = try FileHandle(forWritingTo: destinationURL)

        do {
            defer {
                try? reader.close()
                try? writer.close()
            }

            while true {
                let chunk = try reader.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty {
                    break
                }
                try writer.write(contentsOf: chunk)
            }
        } catch {
            try? writer.close()
            try? reader.close()
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func normalizedUnreadableReason(for error: Error) -> String? {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }

        if Self.genericUnreadableReasons.contains(description) ||
            description.localizedCaseInsensitiveContains("cannot open") ||
            description.localizedCaseInsensitiveContains("couldn’t be opened") ||
            description.localizedCaseInsensitiveContains("could not be opened") ||
            description.localizedCaseInsensitiveContains("invalid data found") ||
            description.localizedCaseInsensitiveContains("moov atom not found") {
            return nil
        }

        return description
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
