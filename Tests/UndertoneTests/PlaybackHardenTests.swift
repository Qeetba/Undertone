import XCTest
import AVFoundation
@testable import UndertoneCore

@MainActor
final class PlaybackHardenTests: XCTestCase {
    private func fixture() throws -> URL {
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

    func testDuplicateURLsWithinOneBatchAreRemoved() {
        var queue = Playlist()
        let url = URL(fileURLWithPath: "/tmp/a.mp3")
        queue.append([url, url, url])
        XCTAssertEqual(queue.count, 1)
    }

    func testEmptyQueueUnloadsCurrentAudio() throws {
        let player = PlayerController()
        player.open(urls: [try fixture()], playImmediately: false)
        XCTAssertGreaterThan(player.duration, 0)
        player.open(urls: [], playImmediately: false)
        XCTAssertNil(player.currentURL)
        XCTAssertEqual(player.duration, 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testUnsupportedSelectionPreservesLoadedAudio() throws {
        let player = PlayerController()
        let url = try fixture()
        player.open(urls: [url], playImmediately: false)
        var errors = 0
        player.onError = { _ in errors += 1 }
        player.open(urls: [URL(fileURLWithPath: "/tmp/photo.png")], playImmediately: false)
        XCTAssertEqual(player.currentURL, url)
        XCTAssertGreaterThan(player.duration, 0)
        XCTAssertEqual(errors, 1)
    }

    func testCorruptFirstFileSkipsToLoadedValidFile() throws {
        let player = PlayerController()
        let valid = try fixture()
        var errors = 0
        player.onError = { _ in errors += 1 }
        player.open(urls: [URL(fileURLWithPath: "/nonexistent/undertone.mp3"), valid], playImmediately: false)
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(player.currentURL, valid)
        XCTAssertGreaterThan(player.duration, 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testAllUnreadableFilesLeaveConsistentEmptyState() {
        let player = PlayerController()
        var errors = 0
        player.onError = { _ in errors += 1 }
        player.open(urls: (0..<30).map { URL(fileURLWithPath: "/nonexistent/undertone-\($0).mp3") }, playImmediately: false)
        XCTAssertEqual(errors, 30)
        XCTAssertNil(player.currentURL)
        XCTAssertEqual(player.playlist.count, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testViewModelClearsMetadataWhenQueueIsCleared() throws {
        let model = NowPlayingViewModel()
        model.player.open(urls: [try fixture()], playImmediately: false)
        XCTAssertNotEqual(model.title, "No Track")
        model.player.open(urls: [], playImmediately: false)
        XCTAssertEqual(model.title, "No Track")
        XCTAssertEqual(model.artist, "")
        XCTAssertNil(model.artwork)
    }

    func testNaturalCompletionAdvancesQueueAndKeepsVolume() throws {
        guard ProcessInfo.processInfo.environment["UNDERTONE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set UNDERTONE_SMOKE_TEST=1 for real playback")
        }
        let player = PlayerController()
        let first = try fixture(), second = try fixture()
        player.volume = 0.15
        var loaded: [URL] = []
        player.onTrackLoaded = { if let url = player.currentURL { loaded.append(url) } }
        player.open(urls: [first, second], playImmediately: true)
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(SmokeTest.waitFor(seconds: 3) { loaded.count == 2 && !player.isPlaying })
        XCTAssertEqual(loaded, [first, second])
        XCTAssertEqual(player.volume, 0.15, accuracy: 0.001)
        XCTAssertEqual(player.currentURL, second)
    }

    func testClearingQueueStopsActivePlayback() throws {
        guard ProcessInfo.processInfo.environment["UNDERTONE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set UNDERTONE_SMOKE_TEST=1 for real playback")
        }
        let player = PlayerController()
        player.open(urls: [try fixture()], playImmediately: true)
        XCTAssertTrue(player.isPlaying)
        player.open(urls: [], playImmediately: false)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentURL)
        XCTAssertEqual(player.currentTime, 0)
    }
}
