import Foundation

/// Owns media asset registry. Single writer for the asset library.
public actor MediaManager {
    public private(set) var assets: [MediaAsset] = []

    public init(assets: [MediaAsset] = []) {
        self.assets = assets
    }

    public func add(_ asset: MediaAsset) {
        assets.append(asset)
    }

    public func remove(id: UUID) {
        assets.removeAll { $0.id == id }
    }

    public func asset(id: UUID) -> MediaAsset? {
        assets.first { $0.id == id }
    }

    public func updateAsset(id: UUID, _ transform: (inout MediaAsset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        transform(&assets[index])
    }

    public func allAssets() -> [MediaAsset] {
        assets
    }
}
