import XCTest
@testable import UndertoneCore

/// Adding to, removing from and reordering a queue that already has audio loaded.
@MainActor
final class QueueEditingTests: XCTestCase {

    /// A controller with `count` real tracks loaded (not playing), plus a counter of track loads.
    private func loadedPlayer(tracks count: Int) throws -> (PlayerController, [URL], () -> Int) {
        let player = PlayerController()
        let urls = try (0..<count).map { _ in try silentWAV() }
        var loads = 0
        player.onTrackLoaded = { loads += 1 }
        player.open(urls: urls, playImmediately: false)
        return (player, urls, { loads })
    }

    private func requireRealPlayback() throws {
        guard ProcessInfo.processInfo.environment["UNDERTONE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set UNDERTONE_SMOKE_TEST=1 for real playback")
        }
    }

    // MARK: - Adding

    func testEnqueueAppendsWithoutReloadingTheCurrentTrack() throws {
        let (player, urls, loads) = try loadedPlayer(tracks: 1)
        let added = try silentWAV()
        player.enqueue(urls: [added])
        XCTAssertEqual(player.playlist.items, [urls[0], added])
        XCTAssertEqual(player.currentURL, urls[0])
        XCTAssertEqual(loads(), 1, "the loaded track must not be reloaded")
    }

    func testEnqueueNotifiesObservers() throws {
        let (player, _, _) = try loadedPlayer(tracks: 1)
        var changes = 0
        player.onChange = { changes += 1 }
        player.enqueue(urls: [try silentWAV()])
        XCTAssertEqual(changes, 1)
    }

    func testEnqueueOfOnlyUnsupportedFilesReportsAnErrorAndKeepsTheQueue() throws {
        let (player, urls, _) = try loadedPlayer(tracks: 1)
        var errors: [String] = []
        player.onError = { errors.append($0) }
        player.enqueue(urls: [URL(fileURLWithPath: "/tmp/photo.png")])
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(player.playlist.items, urls)
    }

    func testEnqueueIntoAnEmptyQueueStartsPlayingTheFirstTrack() throws {
        try requireRealPlayback()
        let player = PlayerController()
        let first = try silentWAV(), second = try silentWAV()
        player.enqueue(urls: [first, second])
        XCTAssertEqual(player.currentURL, first)
        XCTAssertTrue(player.isPlaying)
    }

    func testEnqueueDoesNotInterruptPlayback() throws {
        try requireRealPlayback()
        let player = PlayerController()
        let first = try silentWAV()
        player.open(urls: [first], playImmediately: true)
        player.enqueue(urls: [try silentWAV()])
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentURL, first)
    }

    // MARK: - Removing

    func testRemovingAnotherTrackLeavesTheCurrentTrackLoaded() throws {
        let (player, urls, loads) = try loadedPlayer(tracks: 3)
        player.removeTrack(at: 2)
        XCTAssertEqual(player.playlist.items, [urls[0], urls[1]])
        XCTAssertEqual(player.currentURL, urls[0])
        XCTAssertEqual(loads(), 1, "the loaded track must not be reloaded")
    }

    func testRemovingTheCurrentTrackLoadsTheOneThatFollowed() throws {
        let (player, urls, loads) = try loadedPlayer(tracks: 2)
        player.removeTrack(at: 0)
        XCTAssertEqual(player.currentURL, urls[1])
        XCTAssertGreaterThan(player.duration, 0)
        XCTAssertEqual(loads(), 2)
        XCTAssertFalse(player.isPlaying, "a paused queue stays paused")
    }

    func testRemovingTheOnlyTrackUnloadsAudio() throws {
        let (player, _, _) = try loadedPlayer(tracks: 1)
        player.removeTrack(at: 0)
        XCTAssertNil(player.currentURL)
        XCTAssertEqual(player.duration, 0)
        XCTAssertFalse(player.isPlaying)
    }

    func testRemovingAnOutOfRangeTrackChangesNothing() throws {
        let (player, urls, loads) = try loadedPlayer(tracks: 2)
        player.removeTrack(at: 9)
        XCTAssertEqual(player.playlist.items, urls)
        XCTAssertEqual(loads(), 1)
    }

    func testRemovingThePlayingTrackKeepsPlayingTheNextOne() throws {
        try requireRealPlayback()
        let (player, urls, _) = try loadedPlayer(tracks: 3)
        player.play()
        player.removeTrack(at: 0)
        XCTAssertEqual(player.currentURL, urls[1])
        XCTAssertTrue(player.isPlaying)
    }

    func testRemovingThePlayingLastTrackStopsPlayback() throws {
        try requireRealPlayback()
        let (player, urls, _) = try loadedPlayer(tracks: 2)
        player.selectTrack(1)
        XCTAssertTrue(player.isPlaying)
        player.removeTrack(at: 1)
        XCTAssertEqual(player.currentURL, urls[0])
        XCTAssertFalse(player.isPlaying, "nothing follows the last track, so playback stops")
    }

    // MARK: - Reordering

    func testMovingTracksReordersWithoutReloadingTheCurrentTrack() throws {
        let (player, urls, loads) = try loadedPlayer(tracks: 3)
        var changes = 0
        player.onChange = { changes += 1 }
        player.moveTracks(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(player.playlist.items, [urls[1], urls[2], urls[0]])
        XCTAssertEqual(player.currentURL, urls[0])
        XCTAssertEqual(loads(), 1, "the loaded track must not be reloaded")
        XCTAssertEqual(changes, 1)
    }

    // MARK: - View model

    func testAddToQueuePublishesTheLongerQueue() throws {
        let model = NowPlayingViewModel()
        let first = try silentWAV(), second = try silentWAV()
        model.player.open(urls: [first], playImmediately: false)
        model.addToQueue([second])
        XCTAssertEqual(model.queueItems.map(\.url), [first, second])
        XCTAssertEqual(model.queueItems.map(\.isCurrent), [true, false])
    }

    func testAddToQueueWithNothingPlayableShowsAnError() throws {
        let model = NowPlayingViewModel()
        let first = try silentWAV()
        model.player.open(urls: [first], playImmediately: false)
        model.addToQueue([URL(fileURLWithPath: "/tmp/photo.png")])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.queueItems.map(\.url), [first])
    }

    func testRemoveFromQueuePublishesTheShorterQueue() throws {
        let model = NowPlayingViewModel()
        let first = try silentWAV(), second = try silentWAV()
        model.player.open(urls: [first, second], playImmediately: false)
        model.removeFromQueue(at: 1)
        XCTAssertEqual(model.queueItems.map(\.url), [first])
    }

    func testQueueItemsKeepTheirIdentityWhenReordered() throws {
        let model = NowPlayingViewModel()
        let first = try silentWAV(), second = try silentWAV()
        model.player.open(urls: [first, second], playImmediately: false)
        let idOfFirst = model.queueItems[0].id
        model.moveQueueItems(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(model.queueItems.map(\.url), [second, first])
        XCTAssertEqual(model.queueItems[1].id, idOfFirst, "a row is the same row after it moves")
        XCTAssertEqual(model.queueItems.map(\.index), [0, 1])
        XCTAssertEqual(model.queueItems.map(\.isCurrent), [false, true])
    }
}
