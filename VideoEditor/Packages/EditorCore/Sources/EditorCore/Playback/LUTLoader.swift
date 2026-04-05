import Foundation
import CoreImage

/// Loads .cube LUT files and creates CIFilter instances.
/// Supports standard 3D LUT files in the Adobe .cube format.
public struct LUTLoader: Sendable {

    private final class CacheEntry: NSObject {
        let size: Int
        let data: NSData

        init(size: Int, data: Data) {
            self.size = size
            self.data = data as NSData
        }
    }

    /// Cache parsed cube payloads keyed by file path. CIFilter instances are mutable,
    /// so we create a fresh filter per request to avoid cross-frame state bleed.
    private static nonisolated(unsafe) let cache = NSCache<NSString, CacheEntry>()

    public init() {}

    /// Load and cache a LUT filter from a .cube file. Returns cached if available.
    public static func cachedFilter(at path: String) -> CIFilter? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return createFilter(size: cached.size, data: cached.data as Data)
        }
        guard let (size, data) = try? loadCubeFile(at: URL(fileURLWithPath: path)) else {
            return nil
        }
        cache.setObject(CacheEntry(size: size, data: data), forKey: key)
        return createFilter(size: size, data: data)
    }

    /// Load a .cube file and return the data needed for CIColorCube filter.
    /// Returns (size, data) where size is the cube dimension and data is the flattened RGBA float array.
    public static func loadCubeFile(at url: URL) throws -> (size: Int, data: Data) {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var size = 0
        var values: [Float] = []

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Parse LUT_3D_SIZE
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
                continue
            }

            // Skip other metadata lines (TITLE, DOMAIN_MIN, DOMAIN_MAX)
            if trimmed.contains("TITLE") || trimmed.contains("DOMAIN") { continue }

            // Parse RGB triplets
            let components = trimmed.split(separator: " ")
            if components.count >= 3,
               let r = Float(components[0]),
               let g = Float(components[1]),
               let b = Float(components[2]) {
                values.append(r)
                values.append(g)
                values.append(b)
                values.append(1.0) // alpha
            }
        }

        guard size > 0 else {
            throw LUTError.invalidFormat("No LUT_3D_SIZE found")
        }

        let expectedCount = size * size * size * 4
        guard values.count == expectedCount else {
            throw LUTError.invalidFormat("Expected \(expectedCount) values, got \(values.count)")
        }

        let data = values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        return (size: size, data: data)
    }

    /// Create a CIFilter from a loaded LUT.
    public static func createFilter(size: Int, data: Data) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(CGColorSpaceCreateDeviceRGB(), forKey: "inputColorSpace")
        return filter
    }
}

public enum LUTError: Error, LocalizedError {
    case invalidFormat(String)
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): "Invalid LUT format: \(msg)"
        case .fileNotFound: "LUT file not found"
        }
    }
}
