import Foundation

/// Monitors system memory pressure and triggers degradation responses.
@MainActor @Observable
public final class MemoryPressureMonitor {
    public enum PressureLevel: Int, Comparable, Sendable {
        case normal = 0
        case warning = 1
        case critical = 2

        public static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public private(set) var currentLevel: PressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?
    private var onPressureChange: ((PressureLevel) -> Void)?

    public init() {}

    /// Start monitoring. Call once at app launch.
    public func startMonitoring(onPressureChange: @escaping @Sendable (PressureLevel) -> Void) {
        self.onPressureChange = onPressureChange

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            let level: PressureLevel
            if event.contains(.critical) {
                level = .critical
            } else if event.contains(.warning) {
                level = .warning
            } else {
                level = .normal
            }
            self.currentLevel = level
            onPressureChange(level)
        }
        source.resume()
        self.source = source
    }

    public func stopMonitoring() {
        source?.cancel()
        source = nil
    }
}

// MARK: - Degradation response

/// Defines what happens at each pressure level.
/// Called from AppState when memory pressure changes.
public struct DegradationResponse {

    /// Level 0 (normal): full quality preview
    /// Level 1 (warning): evict caches, pause background jobs
    /// Level 2 (critical): force proxy-only, minimal caches
    public static func respond(
        level: MemoryPressureMonitor.PressureLevel,
        thumbnailCache: DiskCache,
        renderCache: DiskCache,
        proxyService: ProxyService
    ) async {
        switch level {
        case .normal:
            break

        case .warning:
            // Evict render cache from memory (keep on disk)
            // Pause background proxy generation
            await renderCache.clear()

        case .critical:
            // Clear all non-essential caches
            await renderCache.clear()
            await thumbnailCache.clear()
            // Cancel active proxy jobs
            await proxyService.cancelAll()
        }
    }
}
