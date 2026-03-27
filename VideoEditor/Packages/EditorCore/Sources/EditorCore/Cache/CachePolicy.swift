import Foundation

// MARK: - CachePolicy

public struct CachePolicy: Sendable {
    public let name: String
    public let maxSizeBytes: Int64?          // nil = unlimited
    public let maxItemCount: Int?            // nil = unlimited
    public let evictionStrategy: EvictionStrategy

    public init(name: String, maxSizeBytes: Int64? = nil, maxItemCount: Int? = nil, evictionStrategy: EvictionStrategy = .lru) {
        self.name = name
        self.maxSizeBytes = maxSizeBytes
        self.maxItemCount = maxItemCount
        self.evictionStrategy = evictionStrategy
    }

    public enum EvictionStrategy: Sendable {
        case lru            // Least recently used
        case oldest         // Oldest first
        case manual         // Only evict explicitly
    }

    // MARK: - Standard policies

    /// Frame cache: memory, ~200 frames, LRU. Invalidated by seek/edit.
    public static let frameCache = CachePolicy(
        name: "frames",
        maxItemCount: 200,
        evictionStrategy: .lru
    )

    /// Thumbnail cache: disk, unlimited per-asset. Invalidated by re-import.
    public static let thumbnails = CachePolicy(
        name: "thumbnails",
        evictionStrategy: .manual
    )

    /// Waveform cache: disk, unlimited per-asset. Invalidated by re-import.
    public static let waveforms = CachePolicy(
        name: "waveforms",
        evictionStrategy: .manual
    )

    /// Render cache: disk, 2GB max, LRU. Invalidated by timeline edit in cached region.
    public static let renderCache = CachePolicy(
        name: "render",
        maxSizeBytes: 2 * 1024 * 1024 * 1024, // 2GB
        evictionStrategy: .lru
    )

    /// Proxy media: disk, per-project, manual eviction.
    public static let proxies = CachePolicy(
        name: "proxies",
        evictionStrategy: .manual
    )
}

// MARK: - DiskCache

/// Simple disk-backed cache with size tracking and eviction.
public actor DiskCache {
    private let directory: URL
    private let policy: CachePolicy
    private var entries: [String: CacheEntry] = [:]

    public struct CacheEntry: Sendable {
        public let key: String
        public let url: URL
        public let size: Int64
        public var lastAccessed: Date
    }

    public init(directory: URL, policy: CachePolicy) {
        self.directory = directory
        self.policy = policy
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Get the URL for a cache key. Returns nil if not cached.
    public func get(_ key: String) -> URL? {
        guard var entry = entries[key] else { return nil }
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            entries.removeValue(forKey: key)
            return nil
        }
        entry.lastAccessed = Date()
        entries[key] = entry
        return entry.url
    }

    /// Register a file in the cache.
    public func put(_ key: String, url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        entries[key] = CacheEntry(key: key, url: url, size: size, lastAccessed: Date())
        evictIfNeeded()
    }

    /// Remove a specific entry.
    public func remove(_ key: String) {
        if let entry = entries.removeValue(forKey: key) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// Remove all entries.
    public func clear() {
        for entry in entries.values {
            try? FileManager.default.removeItem(at: entry.url)
        }
        entries.removeAll()
    }

    /// Total size of all cached items.
    public func totalSize() -> Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    /// Number of cached items.
    public func count() -> Int {
        entries.count
    }

    // MARK: - Eviction

    private func evictIfNeeded() {
        guard policy.evictionStrategy == .lru else { return }

        // Evict by count
        if let maxCount = policy.maxItemCount, entries.count > maxCount {
            evictLRU(toCount: maxCount)
        }

        // Evict by size
        if let maxSize = policy.maxSizeBytes, totalSize() > maxSize {
            evictLRU(toSize: maxSize)
        }
    }

    private func evictLRU(toCount target: Int) {
        let sorted = entries.values.sorted { $0.lastAccessed < $1.lastAccessed }
        var remaining = entries.count
        for entry in sorted {
            guard remaining > target else { break }
            remove(entry.key)
            remaining -= 1
        }
    }

    private func evictLRU(toSize target: Int64) {
        let sorted = entries.values.sorted { $0.lastAccessed < $1.lastAccessed }
        var currentSize = totalSize()
        for entry in sorted {
            guard currentSize > target else { break }
            currentSize -= entry.size
            remove(entry.key)
        }
    }
}
