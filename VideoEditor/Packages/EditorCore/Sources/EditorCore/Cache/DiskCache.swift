import Foundation

/// Disk-backed cache with size tracking and LRU eviction.
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

    public func put(_ key: String, url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        entries[key] = CacheEntry(key: key, url: url, size: size, lastAccessed: Date())
        evictIfNeeded()
    }

    public func remove(_ key: String) {
        if let entry = entries.removeValue(forKey: key) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    public func clear() {
        for entry in entries.values {
            try? FileManager.default.removeItem(at: entry.url)
        }
        entries.removeAll()
    }

    public func totalSize() -> Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    public func count() -> Int {
        entries.count
    }

    // MARK: - Eviction

    private func evictIfNeeded() {
        guard policy.evictionStrategy == .lru else { return }
        if let maxCount = policy.maxItemCount, entries.count > maxCount {
            evictLRU(toCount: maxCount)
        }
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
