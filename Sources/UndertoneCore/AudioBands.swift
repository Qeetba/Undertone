import Foundation

/// How much energy a short stretch of audio has in its bass, mid and treble ranges,
/// each as an RMS level (a full-scale sine reads about 0.71).
public struct AudioBands: Equatable {
    public var low: Float
    public var mid: Float
    public var high: Float

    public static let silent = AudioBands(low: 0, mid: 0, high: 0)

    public init(low: Float, mid: Float, high: Float) {
        self.low = low
        self.mid = mid
        self.high = high
    }

    /// Bass ends and treble begins at these frequencies (Hz); the mids sit between.
    static let bassCeiling = 200.0
    static let trebleFloor = 2500.0

    /// The leading share of the samples that only settles the filters and is not measured.
    static let warmUpShare = 0.25
    /// Where the middle of the measured part falls, as a share of the samples.
    static let measuredCentre = warmUpShare + (1 - warmUpShare) / 2

    /// Splits mono samples into the three bands and measures each.
    public static func measure(_ samples: [Float], sampleRate: Double) -> AudioBands {
        guard !samples.isEmpty, sampleRate > 0 else { return .silent }
        var bass = Biquad(.lowPass, cutoff: bassCeiling, sampleRate: sampleRate)
        var midFloor = Biquad(.highPass, cutoff: bassCeiling, sampleRate: sampleRate)
        var midCeiling = Biquad(.lowPass, cutoff: trebleFloor, sampleRate: sampleRate)
        var treble = Biquad(.highPass, cutoff: trebleFloor, sampleRate: sampleRate)

        // The filters start from rest, so the first stretch of their output is a
        // start-up transient rather than music. Run them over it, but don't count it.
        let warmUp = Int(Double(samples.count) * warmUpShare)
        var low = 0.0, mid = 0.0, high = 0.0
        for (i, sample) in samples.enumerated() {
            let x = Double(sample)
            let l = bass.process(x)
            let m = midCeiling.process(midFloor.process(x))
            let h = treble.process(x)
            if i >= warmUp {
                low += l * l
                mid += m * m
                high += h * h
            }
        }
        let counted = Double(samples.count - warmUp)
        return AudioBands(low: Float((low / counted).squareRoot()),
                          mid: Float((mid / counted).squareRoot()),
                          high: Float((high / counted).squareRoot()))
    }
}

/// A second-order low- or high-pass filter (Butterworth response, 12 dB per octave).
private struct Biquad {
    enum Kind { case lowPass, highPass }

    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(_ kind: Kind, cutoff: Double, sampleRate: Double) {
        // Keep the cutoff below Nyquist so a low sample rate cannot make the filter unstable.
        let omega = 2 * Double.pi * min(cutoff, sampleRate * 0.45) / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * 0.5.squareRoot())
        let a0 = 1 + alpha
        switch kind {
        case .lowPass:
            b0 = (1 - cosine) / 2 / a0
            b1 = (1 - cosine) / a0
        case .highPass:
            b0 = (1 + cosine) / 2 / a0
            b1 = -(1 + cosine) / a0
        }
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
