import AVFoundation
import XCTest

extension XCTestCase {
    /// Writes 0.3 s of silence to a temporary WAV that is deleted at teardown.
    func silentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("undertone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 13230)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].update(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

extension XCTestCase {
    /// Writes a mono sine tone to a temporary WAV that is deleted at teardown.
    /// `startingAt` leaves that many seconds of silence before the tone begins.
    func toneWAV(frequency: Double, amplitude: Float = 0.5, seconds: Double = 1, startingAt: Double = 0) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("undertone-tone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 44100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            guard Double(i) / 44100 >= startingAt else { samples[i] = 0; continue }
            samples[i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / 44100))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
