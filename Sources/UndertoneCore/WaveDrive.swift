import Foundation

/// Turns raw band levels into three 0...1 values that are pleasant to animate with:
/// scaled so ordinary music uses the whole range, quick to rise so a beat lands on
/// time, and slow to fall so the picture does not flicker.
public struct WaveDrive: Equatable {
    public private(set) var low: Float = 0
    public private(set) var mid: Float = 0
    public private(set) var high: Float = 0

    /// Music carries much less energy in the treble than in the bass, so each band
    /// gets its own gain to bring them to a similar visual strength.
    private static let gain = AudioBands(low: 3.5, mid: 5, high: 12)
    /// Seconds to cover most of the distance to a louder / quieter level.
    private static let attack: Float = 0.03
    private static let release: Float = 0.35

    public init() {}

    /// A drive that has already settled on `bands`, for drawing a still picture.
    public init(settledOn bands: AudioBands) {
        low = Self.strength(bands.low, gain: Self.gain.low)
        mid = Self.strength(bands.mid, gain: Self.gain.mid)
        high = Self.strength(bands.high, gain: Self.gain.high)
    }

    /// Moves toward `bands` by `elapsed` seconds' worth.
    public mutating func update(toward bands: AudioBands, elapsed: TimeInterval) {
        // A long gap (the popover was closed) counts as one slow frame, not a leap.
        let step = Float(min(max(elapsed, 0), 0.1))
        low = Self.follow(low, Self.strength(bands.low, gain: Self.gain.low), step)
        mid = Self.follow(mid, Self.strength(bands.mid, gain: Self.gain.mid), step)
        high = Self.follow(high, Self.strength(bands.high, gain: Self.gain.high), step)
    }

    private static func strength(_ level: Float, gain: Float) -> Float {
        // The power below 1 lifts quiet passages so they still move the waves.
        min(1, pow(max(level, 0) * gain, 0.6))
    }

    private static func follow(_ value: Float, _ target: Float, _ step: Float) -> Float {
        let time = target > value ? attack : release
        return value + (target - value) * (1 - exp(-step / time))
    }
}
