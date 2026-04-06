import Testing
import Foundation
@testable import EditorCore

@Suite("Media Management Tests")
struct MediaManagementTests {

    @Test("MediaManager CRUD keeps assets and proxy URLs in sync")
    func mediaManagerCrud() async {
        let asset = MediaAsset(
            name: "Interview",
            sourceURL: URL(fileURLWithPath: "/tmp/interview.mov"),
            type: .video,
            duration: 12
        )
        let proxyURL = URL(fileURLWithPath: "/tmp/interview-proxy.mov")
        let manager = MediaManager()

        await manager.add(asset)
        #expect(await manager.asset(id: asset.id)?.name == "Interview")

        await manager.setProxyURL(proxyURL, for: asset.id)
        #expect(await manager.asset(id: asset.id)?.proxyURL == proxyURL)

        await manager.updateAsset(id: asset.id) { storedAsset in
            storedAsset.name = "Interview B-Roll"
        }
        #expect(await manager.allAssets().map(\.name) == ["Interview B-Roll"])

        await manager.remove(id: asset.id)
        #expect(await manager.asset(id: asset.id) == nil)
        #expect(await manager.allAssets().isEmpty)
    }

    @Test("MediaImporter copyToBundle preserves extension and uses asset ID")
    func copyToBundlePreservesExtension() throws {
        let importer = MediaImporter()
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).mov")
        let bundleMediaDir = fileManager.temporaryDirectory.appendingPathComponent("bundle-media-\(UUID().uuidString)", isDirectory: true)
        let assetID = UUID()

        try fileManager.createDirectory(at: bundleMediaDir, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: sourceURL)
        defer {
            try? fileManager.removeItem(at: sourceURL)
            try? fileManager.removeItem(at: bundleMediaDir)
        }

        let copiedURL = try importer.copyToBundle(sourceURL: sourceURL, bundleMediaDir: bundleMediaDir, assetID: assetID)

        #expect(copiedURL.lastPathComponent == "\(assetID.uuidString).mov")
        #expect(fileManager.fileExists(atPath: copiedURL.path))
        #expect(try String(contentsOf: copiedURL) == "fixture")
    }

    @Test("FourCharCode helper renders ASCII codes")
    func fourCharCodeFormatting() {
        #expect(FourCharCode(0x61766331).fourCharString == "avc1")
    }

    @Test("MediaImporter detects image assets and reads dimensions")
    func importImageAsset() async throws {
        let importer = MediaImporter()
        let fileManager = FileManager.default
        let imageURL = fileManager.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).png")
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlAbWQAAAAASUVORK5CYII=")!
        try pngData.write(to: imageURL)
        defer { try? fileManager.removeItem(at: imageURL) }

        let asset = try await importer.importFile(from: imageURL)

        #expect(asset.type == .image)
        #expect(asset.width == 1)
        #expect(asset.height == 1)
        #expect(asset.duration == 0)
    }

    @Test("MediaImporter rejects unsupported files")
    func rejectUnsupportedFile() async {
        let importer = MediaImporter()
        let fileManager = FileManager.default
        let unsupportedURL = fileManager.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).txt")
        try? Data("not media".utf8).write(to: unsupportedURL)
        defer { try? fileManager.removeItem(at: unsupportedURL) }

        await #expect(throws: MediaImporter.ImportError.self) {
            try await importer.importFile(from: unsupportedURL)
        }
    }

    @Test("MediaImporter reports unreadable movie files clearly")
    func rejectUnreadableMovieFile() async {
        let importer = MediaImporter()
        let fileManager = FileManager.default
        let movieURL = fileManager.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).mov")
        try? Data("broken movie".utf8).write(to: movieURL)
        defer { try? fileManager.removeItem(at: movieURL) }

        do {
            try await importer.importFile(from: movieURL)
            Issue.record("Expected unreadable movie import to fail")
        } catch let error as MediaImporter.ImportError {
            #expect(
                error.errorDescription ==
                "Could not open media file \(movieURL.lastPathComponent). The file may be incomplete or corrupted."
            )
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("MediaManager imports images into the bundle and caches thumbnails")
    func importImageIntoBundle() async throws {
        let manager = MediaManager()
        let fileManager = FileManager.default
        let imageURL = fileManager.temporaryDirectory.appendingPathComponent("bundle-image-\(UUID().uuidString).png")
        let bundleMediaDir = fileManager.temporaryDirectory.appendingPathComponent("bundle-images-\(UUID().uuidString)", isDirectory: true)
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlAbWQAAAAASUVORK5CYII=")!
        try fileManager.createDirectory(at: bundleMediaDir, withIntermediateDirectories: true)
        try pngData.write(to: imageURL)
        defer {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: bundleMediaDir)
        }

        let asset = try await manager.importFile(from: imageURL, bundleMediaDir: bundleMediaDir)

        #expect(asset.type == .image)
        #expect(asset.sourceURL.deletingLastPathComponent() == bundleMediaDir)
        #expect(fileManager.fileExists(atPath: asset.sourceURL.path))
        #expect(await manager.thumbnail(for: asset.id) != nil)
    }

    @Test("MediaManager lazily generates thumbnails for loaded images")
    func lazyThumbnailGenerationForLoadedImage() async throws {
        let manager = MediaManager()
        let fileManager = FileManager.default
        let imageURL = fileManager.temporaryDirectory.appendingPathComponent("lazy-thumb-\(UUID().uuidString).png")
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlAbWQAAAAASUVORK5CYII=")!
        try pngData.write(to: imageURL)
        defer { try? fileManager.removeItem(at: imageURL) }

        let asset = MediaAsset(
            name: "Lazy Thumbnail",
            sourceURL: imageURL,
            type: .image,
            duration: 0,
            width: 1,
            height: 1
        )

        await manager.add(asset)

        #expect(await manager.thumbnail(for: asset.id) != nil)
    }
}
