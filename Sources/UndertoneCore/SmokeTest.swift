import AVFoundation
import Foundation

/// Headless end-to-end smoke check: loads real audio files with AVAudioPlayer,
/// plays, pauses, seeks, and verifies natural completion for each format.
/// Run with: `swift run Undertone --smoke-test` (or the bundled app binary).
public enum SmokeTest {
    final class CompletionDelegate: NSObject, AVAudioPlayerDelegate {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            success = flag
            semaphore.signal()
        }
    }

    public static func run(
        directory: String = "/tmp/undertone-verification",
        formats: [String] = ["wav", "mp3", "m4a", "flac"],
        out: (String) -> Void = { print($0) }
    ) -> Int32 {
        var failures = 0
        out("Undertone smoke test — directory: \(directory)")
        for ext in formats {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("tone.\(ext)")
            let name = url.lastPathComponent
            if runCase(url: url, out: out) {
                out("PASS  \(name)  (load / play / pause / seek / completion)")
            } else {
                out("FAIL  \(name)")
                failures += 1
            }
        }
        if failures == 0 {
            out("ALL \(formats.count) FORMATS PASSED")
            return 0
        }
        out("\(failures) of \(formats.count) formats FAILED")
        return 1
    }

    private static func runCase(url: URL, out: (String) -> Void = { _ in }) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("    missing fixture: \(url.path)")
            return false
        }

        // 1. Load
        let delegate = CompletionDelegate()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            print("    load error: \(error.localizedDescription)")
            return false
        }
        player.delegate = delegate
        guard player.duration > 1.0, player.duration < 5.0 else {
            print("    unexpected duration: \(player.duration)")
            return false
        }
        guard player.prepareToPlay() else { return false }

        // 2. Play
        guard player.play() else { return false }
        guard waitFor(seconds: 3, condition: { player.isPlaying }) else {
            print("    never started playing")
            return false
        }

        // 3. Confirm actually playing for a moment
        busyRunLoop(seconds: 0.4)
        guard player.isPlaying else {
            print("    stopped immediately after start")
            return false
        }

        // 4. Pause
        player.pause()
        guard !player.isPlaying else {
            print("    pause did not take effect")
            return false
        }

        // 5. Seek to the middle and play to completion
        let mid = player.duration / 2
        player.currentTime = mid
        guard abs(player.currentTime - mid) < 0.3 else {
            print("    seek did not take effect: \(player.currentTime) vs \(mid)")
            return false
        }
        guard player.play() else { return false }

        // 6. Wait for delegate completion callback (delivered on this thread's
        // run loop, so we must keep pumping it rather than blocking).
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if delegate.success { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        guard delegate.success else {
            print("    no completion callback within 20s")
            return false
        }
        guard delegate.success else {
            print("    completion reported failure")
            return false
        }
        return true
    }

    /// Polls a condition while keeping the run loop alive (timers/delegates keep firing).
    public static func waitFor(seconds: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    public static func busyRunLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
