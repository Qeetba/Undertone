import AVFoundation
import Foundation

/// Reads the bands of an audio file at any playback position, so a visualizer can
/// show what is being heard right now. It decodes the file itself, alongside the
/// player, because AVAudioPlayer does not expose the samples it plays.
public final class TrackAnalyzer {
    /// Frames measured per reading: about 46 ms at 44.1 kHz, enough to catch bass.
    static let window = 2048

    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let sampleRate: Double
    /// Mixed-down samples already decoded, starting at frame `cachedStart`. Playback
    /// moves forward a little each reading, so most of a window is reused and the
    /// file is read straight through instead of seeking every time.
    private var cached: [Float] = []
    private var cachedStart: AVAudioFramePosition = 0

    public init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(Self.window)) else {
            throw NSError(domain: "Undertone.Analysis", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not allocate an analysis buffer."])
        }
        self.buffer = buffer
        sampleRate = file.processingFormat.sampleRate
    }

    /// The bands of the audio around `time` seconds. Silent outside the file.
    public func bands(at time: TimeInterval) -> AudioBands {
        let now = AVAudioFramePosition(time * sampleRate)
        guard time >= 0, now < file.length else { return .silent }
        // Place the window so the part that gets measured is centred on `time`;
        // starting it at `time` would show every sound a moment before it is heard.
        let lead = AVAudioFramePosition(Double(Self.window) * AudioBands.measuredCentre)
        let start = max(0, now - lead)

        let cachedEnd = cachedStart + AVAudioFramePosition(cached.count)
        if start >= cachedStart, start <= cachedEnd {
            cached.removeFirst(Int(start - cachedStart))
        } else {
            cached.removeAll(keepingCapacity: true)
            file.framePosition = start
        }
        cachedStart = start

        while cached.count < Self.window {
            let wanted = AVAudioFrameCount(Self.window - cached.count)
            guard (try? file.read(into: buffer, frameCount: wanted)) != nil, buffer.frameLength > 0 else { break }
            appendMixdown()
        }
        return AudioBands.measure(cached, sampleRate: sampleRate)
    }

    /// Averages the buffer's channels into mono and adds the result to the cache.
    private func appendMixdown() {
        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channelCount { sum += channels[channel][frame] }
            cached.append(sum / Float(channelCount))
        }
    }
}
