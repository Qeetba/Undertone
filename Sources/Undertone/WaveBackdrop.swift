import SwiftUI
import UndertoneCore

/// Three layered waves that move with the music, drawn behind the player controls.
/// Bass drives the big slow wave at the back, mids the one in the middle, and treble
/// a fine ripple in front.
struct WaveBackdrop: View {
    /// Animate only while this is true (the popover is on screen).
    let isRunning: Bool
    /// The levels of what is playing right now; asked once per frame.
    let bands: () -> AudioBands
    @State private var motion: WaveMotion

    /// - Parameter settledOn: start already moving to these levels, for a still picture.
    init(isRunning: Bool, settledOn still: AudioBands? = nil, bands: @escaping () -> AudioBands) {
        self.isRunning = isRunning
        self.bands = bands
        _motion = State(initialValue: WaveMotion(settledOn: still))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRunning)) { timeline in
            let frame = motion.advance(to: timeline.date, bands: bands())
            Canvas { context, size in
                // Screen blending: where waves overlap they brighten instead of going muddy.
                context.blendMode = .screen
                for layer in WaveLayer.all {
                    layer.draw(in: &context, size: size, frame: frame)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One moment of the animation: how strongly each wave is driven and how far along it has travelled.
private struct WaveFrame {
    var drive: WaveDrive
    var travel: Double
}

/// The animation's memory between frames. A reference type on purpose: advancing it
/// must not invalidate the view the way changing observed state would.
private final class WaveMotion {
    private var drive: WaveDrive
    private var travel: Double
    private var lastFrame: Date?

    init(settledOn still: AudioBands?) {
        drive = still.map(WaveDrive.init(settledOn:)) ?? WaveDrive()
        travel = still == nil ? 0 : 2.6
    }

    func advance(to date: Date, bands: AudioBands) -> WaveFrame {
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        drive.update(toward: bands, elapsed: elapsed)
        // The waves always drift, and travel faster the more there is to hear.
        let energy = Double(drive.low + drive.mid + drive.high) / 3
        travel += min(max(elapsed, 0), 0.1) * (0.45 + 1.8 * energy)
        return WaveFrame(drive: drive, travel: travel)
    }
}

private struct WaveLayer {
    let color: Color
    let band: KeyPath<WaveDrive, Float>
    /// Resting height of the crest line, in points from the top of the popover.
    let crest: CGFloat
    /// How far the crests swing at full strength.
    let swing: CGFloat
    /// Length of one wave, as a fraction of the popover's width.
    let wavelength: Double
    /// How fast, and which way, it travels.
    let speed: Double
    let offset: Double
    let fill: Double

    /// Each wave's colour fades out this far below its crest line, which keeps the
    /// queue drawer underneath clear.
    static let fadeDepth: CGFloat = 105

    static let all = [
        WaveLayer(color: Color(red: 0.41, green: 0.94, blue: 0.76), band: \.low,
                  crest: 224, swing: 44, wavelength: 1.3, speed: 0.55, offset: 0.0, fill: 0.30),
        WaveLayer(color: Color(red: 1.00, green: 0.50, blue: 0.42), band: \.mid,
                  crest: 242, swing: 28, wavelength: 0.72, speed: -0.85, offset: 2.1, fill: 0.20),
        WaveLayer(color: Color(red: 0.74, green: 1.00, blue: 0.92), band: \.high,
                  crest: 258, swing: 12, wavelength: 0.31, speed: 1.6, offset: 4.4, fill: 0.12),
    ]

    func draw(in context: inout GraphicsContext, size: CGSize, frame: WaveFrame) {
        let strength = Double(frame.drive[keyPath: band])
        let phase = frame.travel * speed + offset
        // A resting wave still ripples a little; a loud one both swings and rises.
        let amplitude = swing * (0.14 + 0.86 * strength)
        let level = crest - swing * 0.6 * strength

        var line = Path()
        var x: CGFloat = 0
        while x <= size.width + 3 {
            let u = Double(x / size.width)
            let primary = sin(2 * .pi * u / wavelength + phase)
            let secondary = sin(2 * .pi * u / (wavelength * 0.43) - phase * 1.4 + offset * 1.7)
            let bulge = 0.8 + 0.2 * sin(2 * .pi * u * 0.6 + phase * 0.3 + offset)
            let y = level - amplitude * bulge * (0.62 * primary + 0.38 * secondary)
            if x == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            x += 3
        }

        var body = line
        body.addLine(to: CGPoint(x: size.width + 3, y: size.height))
        body.addLine(to: CGPoint(x: 0, y: size.height))
        body.closeSubpath()
        let depth = fill * (0.5 + 0.5 * strength)
        context.fill(body, with: .linearGradient(
            Gradient(colors: [color.opacity(depth), color.opacity(0)]),
            startPoint: CGPoint(x: 0, y: level - amplitude),
            endPoint: CGPoint(x: 0, y: level + Self.fadeDepth)))

        // A soft glow under a thin bright crest.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 5))
            glow.stroke(line, with: .color(color.opacity(0.18 + 0.45 * strength)), lineWidth: 3)
        }
        context.stroke(line, with: .color(color.opacity(0.22 + 0.5 * strength)), lineWidth: 1)
    }
}
