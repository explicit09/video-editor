import Foundation

// MARK: - CachePolicy

public struct CachePolicy: Sendable {
    public let name: String
    public let maxSizeBytes: Int64?
    public let maxItemCount: Int?
    public let evictionStrategy: EvictionStrategy

    public init(name: String, maxSizeBytes: Int64? = nil, maxItemCount: Int? = nil, evictionStrategy: EvictionStrategy = .lru) {
        self.name = name
        self.maxSizeBytes = maxSizeBytes
        self.maxItemCount = maxItemCount
        self.evictionStrategy = evictionStrategy
    }

    public enum EvictionStrategy: Sendable {
        case lru
        case oldest
        case manual
    }

    // MARK: - Standard policies

    public static let frameCache = CachePolicy(name: "frames", maxItemCount: 200, evictionStrategy: .lru)
    public static let thumbnails = CachePolicy(name: "thumbnails", evictionStrategy: .manual)
    public static let waveforms = CachePolicy(name: "waveforms", evictionStrategy: .manual)
    public static let renderCache = CachePolicy(name: "render", maxSizeBytes: 2 * 1024 * 1024 * 1024, evictionStrategy: .lru)
    public static let proxies = CachePolicy(name: "proxies", evictionStrategy: .manual)
}
