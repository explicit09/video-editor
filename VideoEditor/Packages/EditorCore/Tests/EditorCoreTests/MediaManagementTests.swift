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
}
