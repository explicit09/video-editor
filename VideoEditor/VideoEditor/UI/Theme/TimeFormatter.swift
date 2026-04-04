import Foundation

/// Shared time formatting utilities — single source of truth.
enum TimeFormatter {

    /// Full timecode: HH:MM:SS:FF (at 30fps)
    static func timecode(_ time: TimeInterval, fps: Int = 30) -> String {
        let t = max(0, time)
        let hrs = Int(t) / 3600
        let mins = (Int(t) % 3600) / 60
        let secs = Int(t) % 60
        let frames = Int((t - Double(Int(t))) * Double(fps))
        return String(format: "%02d:%02d:%02d:%02d", hrs, mins, secs, frames)
    }

    /// Short duration: M:SS
    static func duration(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Medium duration: HH:MM:SS
    static func durationHMS(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let hrs = Int(t) / 3600
        let mins = (Int(t) % 3600) / 60
        let secs = Int(t) % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }

    /// Ruler timecode: context-dependent (omits hours when < 1hr)
    static func rulerTimecode(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        let frames = Int((time - Double(Int(time))) * 30)
        if mins > 0 {
            return String(format: "%d:%02d:%02d", mins, secs, frames)
        }
        return String(format: "%d:%02d", secs, frames)
    }
}
