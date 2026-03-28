import Foundation

/// Interpolates keyframe values at a given time.
/// Used by CompositionBuilder to resolve animated properties.
public struct KeyframeInterpolator: Sendable {

    public init() {}

    /// Get the interpolated value at a given time from a keyframe track.
    public func value(at time: TimeInterval, keyframes: [Keyframe]) -> Double? {
        guard !keyframes.isEmpty else { return nil }

        let sorted = keyframes.sorted { $0.time < $1.time }

        // Before first keyframe
        if time <= sorted[0].time { return sorted[0].value }

        // After last keyframe
        if time >= sorted[sorted.count - 1].time { return sorted[sorted.count - 1].value }

        // Find surrounding keyframes
        for i in 0..<(sorted.count - 1) {
            let k1 = sorted[i]
            let k2 = sorted[i + 1]

            if time >= k1.time && time <= k2.time {
                let t = (time - k1.time) / (k2.time - k1.time) // 0-1 progress

                switch k1.interpolation {
                case .linear:
                    return k1.value + (k2.value - k1.value) * t
                case .hold:
                    return k1.value
                case .easeIn:
                    let curved = t * t // Quadratic ease in
                    return k1.value + (k2.value - k1.value) * curved
                case .easeOut:
                    let curved = 1 - (1 - t) * (1 - t) // Quadratic ease out
                    return k1.value + (k2.value - k1.value) * curved
                case .easeInOut:
                    let curved = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                    return k1.value + (k2.value - k1.value) * curved
                }
            }
        }

        return sorted.last?.value
    }

    /// Generate volume ramp points for AVAudioMix from keyframes.
    /// Returns (time, volume) pairs suitable for setVolumeRamp.
    public func volumeRamps(from keyframes: [Keyframe], baseVolume: Double = 1.0) -> [(time: TimeInterval, volume: Float)] {
        let sorted = keyframes.sorted { $0.time < $1.time }
        return sorted.map { kf in
            (time: kf.time, volume: Float(kf.value * baseVolume))
        }
    }
}
