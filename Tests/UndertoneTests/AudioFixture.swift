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
