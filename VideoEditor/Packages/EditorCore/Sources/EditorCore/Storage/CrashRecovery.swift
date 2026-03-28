import Foundation

/// Crash recovery: detects unclean shutdown and restores last auto-save.
/// Uses a lock file that's created on launch and removed on clean exit.
public actor CrashRecovery {
    private let lockURL: URL
    private let projectBundleURL: URL

    public init(projectBundleURL: URL) {
        self.projectBundleURL = projectBundleURL
        self.lockURL = projectBundleURL.appendingPathComponent(".session.lock")
    }

    /// Check if the previous session crashed (lock file exists from last launch).
    public func didCrash() -> Bool {
        FileManager.default.fileExists(atPath: lockURL.path)
    }

    /// Create lock file on startup. If it already exists, previous session crashed.
    public func startSession() throws {
        let sessionInfo: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "startTime": ISO8601DateFormatter().string(from: Date()),
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        ]
        let data = try JSONSerialization.data(withJSONObject: sessionInfo)
        try data.write(to: lockURL)
    }

    /// Remove lock file on clean exit.
    public func endSession() {
        try? FileManager.default.removeItem(at: lockURL)
    }

    /// Get the timestamp of the last auto-save for recovery.
    public func lastAutoSaveTime() -> Date? {
        let timelinePath = projectBundleURL.appendingPathComponent("timeline.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: timelinePath.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }

    /// Recovery info for displaying to the user.
    public struct RecoveryInfo: Sendable {
        public let lastSaveTime: Date?
        public let previousPID: Int32?
        public let previousStartTime: String?
    }

    /// Get recovery information from the crash lock file.
    public func recoveryInfo() -> RecoveryInfo? {
        guard let data = try? Data(contentsOf: lockURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return RecoveryInfo(
            lastSaveTime: lastAutoSaveTime(),
            previousPID: json["pid"] as? Int32,
            previousStartTime: json["startTime"] as? String
        )
    }
}
