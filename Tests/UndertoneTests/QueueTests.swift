import XCTest
@testable import UndertoneCore

final class QueueTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/fake/\(name).mp3")
    }

    // MARK: - Playlist append / order

    func testAppendPreservesOrder() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        XCTAssertEqual(q.items.map(\.lastPathComponent), ["a.mp3", "b.mp3", "c.mp3"])
        XCTAssertEqual(q.count, 3)
        XCTAssertEqual(q.current, url("a"), "first appended file becomes current")
    }

    func testAppendSkipsDuplicates() {
        var q = Playlist()
        q.append([url("a"), url("b")])
        q.append([url("b"), url("c")])
        XCTAssertEqual(q.count, 3)
        XCTAssertEqual(q.items.map(\.lastPathComponent), ["a.mp3", "b.mp3", "c.mp3"])
    }

    func testEmptyQueueHasNoCurrent() {
        var q = Playlist()
        XCTAssertNil(q.current)
        XCTAssertNil(q.currentIndex)
        XCTAssertTrue(q.isEmpty)
        q.append([])
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.current)
    }

    // MARK: - Next / previous semantics

    func testAdvanceWalksQueueAndStopsAtEnd() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        XCTAssertEqual(q.advance(), url("b"))
        XCTAssertEqual(q.advance(), url("c"))
        XCTAssertNil(q.advance(), "no wraparound past the end")
        XCTAssertEqual(q.current, url("c"), "stays on last track at end")
    }

    func testRewindWalksBackAndStopsAtStart() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.select(2)
        XCTAssertEqual(q.rewind(), url("b"))
        XCTAssertEqual(q.rewind(), url("a"))
        XCTAssertNil(q.rewind(), "cannot go before the first track")
        XCTAssertEqual(q.current, url("a"))
    }

    func testAdvanceAndRewindOnEmptyQueueAreNil() {
        var q = Playlist()
        XCTAssertNil(q.advance())
        XCTAssertNil(q.rewind())
        XCTAssertNil(q.select(0))
    }

    // MARK: - Selection / replacement

    func testSelectTrackPicksArbitraryIndex() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        XCTAssertEqual(q.select(1), url("b"))
        XCTAssertEqual(q.current, url("b"))
        XCTAssertNil(q.select(99), "out-of-range select is rejected")
        XCTAssertEqual(q.current, url("b"), "state unchanged after bad select")
    }

    func testReplaceAllResetsAndPlaysFirst() {
        var q = Playlist()
        q.append([url("a"), url("b")])
        q.select(1)
        q.replaceAll(with: [url("x"), url("y")])
        XCTAssertEqual(q.items.map(\.lastPathComponent), ["x.mp3", "y.mp3"])
        XCTAssertEqual(q.currentIndex, 0, "replacement queue starts at first file")
        XCTAssertEqual(q.current, url("x"))
    }

    func testClearEmptiesEverything() {
        var q = Playlist()
        q.append([url("a")])
        q.clear()
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.current)
    }

    // MARK: - Removing

    func testRemoveBeforeCurrentKeepsTheSameTrackCurrent() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.select(2)
        XCTAssertFalse(q.remove(at: 0), "the current track was not the one removed")
        XCTAssertEqual(q.items, [url("b"), url("c")])
        XCTAssertEqual(q.current, url("c"))
    }

    func testRemoveAfterCurrentKeepsTheSameTrackCurrent() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        XCTAssertFalse(q.remove(at: 2))
        XCTAssertEqual(q.items, [url("a"), url("b")])
        XCTAssertEqual(q.current, url("a"))
    }

    func testRemoveCurrentMovesToTheTrackThatFollowed() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.select(1)
        XCTAssertTrue(q.remove(at: 1), "the current track was the one removed")
        XCTAssertEqual(q.items, [url("a"), url("c")])
        XCTAssertEqual(q.current, url("c"))
    }

    func testRemoveCurrentAtTheEndFallsBackToTheNewLastTrack() {
        var q = Playlist()
        q.append([url("a"), url("b")])
        q.select(1)
        XCTAssertTrue(q.remove(at: 1))
        XCTAssertEqual(q.current, url("a"))
    }

    func testRemoveOnlyTrackEmptiesTheQueue() {
        var q = Playlist()
        q.append([url("a")])
        XCTAssertTrue(q.remove(at: 0))
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.currentIndex)
    }

    func testRemoveOutOfRangeChangesNothing() {
        var q = Playlist()
        q.append([url("a"), url("b")])
        XCTAssertFalse(q.remove(at: 5))
        XCTAssertFalse(q.remove(at: -1))
        XCTAssertEqual(q.items, [url("a"), url("b")])
        XCTAssertEqual(q.current, url("a"))
    }

    // MARK: - Reordering (same contract as SwiftUI's onMove: offsets + insertion point)

    func testMoveTrackDownReordersItems() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(q.items, [url("b"), url("c"), url("a")])
    }

    func testMoveTrackUpReordersItems() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(q.items, [url("c"), url("a"), url("b")])
    }

    func testMovingTheCurrentTrackKeepsItCurrent() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(q.items, [url("b"), url("a"), url("c")])
        XCTAssertEqual(q.current, url("a"))
        XCTAssertEqual(q.currentIndex, 1)
    }

    func testMovingAnotherTrackPastTheCurrentOneKeepsItCurrent() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c")])
        q.select(1)
        q.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(q.current, url("b"))
        XCTAssertEqual(q.currentIndex, 2)
    }

    func testMoveSeveralTracksKeepsTheirRelativeOrder() {
        var q = Playlist()
        q.append([url("a"), url("b"), url("c"), url("d")])
        q.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(q.items, [url("b"), url("d"), url("a"), url("c")])
    }

    func testMoveWithOutOfRangeOffsetsChangesNothing() {
        var q = Playlist()
        q.append([url("a"), url("b")])
        q.move(fromOffsets: IndexSet(integer: 7), toOffset: 0)
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 9)
        XCTAssertEqual(q.items, [url("a"), url("b")])
        XCTAssertEqual(q.current, url("a"))
    }

    // MARK: - Supported file filtering

    func testSupportedAudioFilterKeepsOnlyAudioExtensions() {
        let urls = [
            url("song"),                                    // .mp3 → kept
            URL(fileURLWithPath: "/tmp/fake/track.flac"),
            URL(fileURLWithPath: "/tmp/fake/voice.m4a"),
            URL(fileURLWithPath: "/tmp/fake/notes.wav"),
            URL(fileURLWithPath: "/tmp/fake/readme.txt"),
            URL(fileURLWithPath: "/tmp/fake/pic.png"),
        ]
        let kept = SupportedAudio.filter(urls)
        XCTAssertEqual(kept.count, 4)
        XCTAssertFalse(kept.contains { $0.pathExtension == "txt" })
        XCTAssertFalse(kept.contains { $0.pathExtension == "png" })
    }

    // MARK: - PlayerController error surfacing

    func testPlayerReportsErrorForMissingFile() {
        let player = PlayerController()
        let exp = expectation(description: "onError fires")
        var message: String?
        player.onError = { m in
            message = m
            exp.fulfill()
        }
        player.open(urls: [URL(fileURLWithPath: "/tmp/undertone-does-not-exist/none.mp3")], playImmediately: false)
        wait(for: [exp], timeout: 2)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("none.mp3") ?? false, "error should name the file")
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentURL)
    }

    func testPlayerErrorCallbackSetThroughOpenOfEmptyQueue() {
        let player = PlayerController()
        var messages: [String] = []
        player.onError = { messages.append($0) }
        player.open(urls: [], playImmediately: true)
        XCTAssertTrue(messages.isEmpty, "opening an empty list is a no-op, not an error")
        XCTAssertNil(player.currentURL)
    }
}
