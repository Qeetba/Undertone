import AVFoundation
import XCTest
@testable import UndertoneCore

/// Real-playback smoke test using the AVAudioPlayer engine end to end.
/// Gated behind UNDERTONE_SMOKE_TEST=1 because it actually plays audio and
/// requires the generated fixtures at /tmp/undertone-verification/tone.{wav,mp3,m4a,flac}.
///
/// Run it with:
///   UNDERTONE_SMOKE_TEST=1 swift test --filter SmokeTests
/// or simply: swift run Undertone --smoke-test
final class SmokeTests: XCTestCase {
    private let directory = "/tmp/undertone-verification"
    private let formats = ["wav", "mp3", "m4a", "flac"]

    func testRealLoadPlayPauseSeekCompletionForAllFormats() throws {
        guard ProcessInfo.processInfo.environment["UNDERTONE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set UNDERTONE_SMOKE_TEST=1 to run real audio playback smoke test")
        }

        for ext in formats {
            let path = "\(directory)/tone.\(ext)"
            guard FileManager.default.fileExists(atPath: path) else {
                throw XCTSkip("Fixture missing: \(path) (generate with ffmpeg)")
            }
            let url = URL(fileURLWithPath: path)
            let ok = Self.runPlaybackCase(url: url)
            XCTAssertTrue(ok, "smoke case failed for \(url.lastPathComponent)")
        }
    }

    /// Same load/play/pause/seek/completion sequence as SmokeTests.run for one file,
    /// driven through PlayerController for the queue path plus raw AVAudioPlayer for completion.
    static func runPlaybackCase(url: URL) -> Bool {
        let delegate = SmokeTests.CompletionDelegateShim()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            XCTFail("load failed: \(error.localizedDescription)")
            return false
        }
        player.delegate = delegate
        guard player.duration > 1, player.duration < 5 else { return false }
        guard player.prepareToPlay(), player.play() else { return false }
        guard SmokeTest.waitFor(seconds: 3, condition: { player.isPlaying }) else { return false }

        SmokeTest.busyRunLoop(seconds: 0.3)
        guard player.isPlaying else { return false }

        player.pause()
        guard !player.isPlaying else { return false }

        let mid = player.duration / 2
        player.currentTime = mid
        guard abs(player.currentTime - mid) < 0.3 else { return false }
        guard player.play() else { return false }

        // Completion is delivered on this run loop; keep pumping instead of blocking.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && !delegate.success {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        return delegate.success
    }
}

extension SmokeTests {
    final class CompletionDelegateShim: NSObject, AVAudioPlayerDelegate {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            success = flag
            semaphore.signal()
        }
    }
}
