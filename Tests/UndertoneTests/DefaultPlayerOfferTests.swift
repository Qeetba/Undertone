import UniformTypeIdentifiers
import XCTest
@testable import UndertoneCore

/// Stands in for Launch Services: records what was asked, changes nothing on the machine.
private final class FakeSystem: DefaultAppSystem {
    var appBundleURL: URL? = URL(fileURLWithPath: "/Applications/Undertone.app")
    var appBundleID: String? = "com.undertone.audio"
    /// Current handler per extension; anything not listed belongs to `otherApp`.
    var handlers: [String: String] = [:]
    var otherApp: String? = "com.apple.Music"
    var failingExtensions: Set<String> = []
    private(set) var setCalls: [(appURL: URL, ext: String)] = []

    func defaultAppBundleID(for type: UTType) -> String? {
        handlers[ext(type)] ?? otherApp
    }

    func setDefaultApp(at appURL: URL, for type: UTType) async throws {
        let e = ext(type)
        setCalls.append((appURL, e))
        if failingExtensions.contains(e) {
            throw NSError(domain: "FakeSystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "refused \(e)"])
        }
        handlers[e] = appBundleID
    }

    func ownAll() {
        for e in DefaultPlayerOffer.extensions { handlers[e] = appBundleID }
    }

    private func ext(_ type: UTType) -> String {
        DefaultPlayerOffer.extensions.first { UTType(filenameExtension: $0) == type } ?? type.identifier
    }
}

/// Keeps the saved answer in memory, so tests leave nothing in ~/Library/Preferences.
private final class MemoryStore: DefaultPlayerAnswerStore {
    var answered = false
}

@MainActor
final class DefaultPlayerOfferTests: XCTestCase {
    private var system: FakeSystem!
    private var store: MemoryStore!

    override func setUp() {
        super.setUp()
        system = FakeSystem()
        store = MemoryStore()
    }

    private func makeOffer(force: Bool = false) -> DefaultPlayerOffer {
        DefaultPlayerOffer(system: system, store: store, forceOffer: force)
    }

    private var answered: Bool { store.answered }

    // MARK: - When to ask

    func testOffersOnFirstRunFromBundle() {
        XCTAssertTrue(makeOffer().shouldOffer())
    }

    func testSkipsOnceAnswered() {
        store.answered = true
        XCTAssertFalse(makeOffer().shouldOffer())
    }

    func testSkipsWithoutBundle() {
        system.appBundleURL = nil // `swift run`: nothing for macOS to register
        XCTAssertFalse(makeOffer().shouldOffer())
        XCTAssertFalse(answered, "not being able to ask is not an answer")
    }

    func testSkipsWhileTranslocated() {
        system.appBundleURL = URL(fileURLWithPath:
            "/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/Undertone.app")
        XCTAssertFalse(makeOffer().shouldOffer())
        XCTAssertFalse(answered, "should ask on a later launch from a real location")
    }

    func testAlreadyDefaultSavesAnswerAndSkips() {
        system.ownAll()
        XCTAssertFalse(makeOffer().shouldOffer())
        XCTAssertTrue(answered)
    }

    func testPartlyDefaultStillOffers() {
        system.ownAll()
        system.handlers["flac"] = "org.audacityteam.audacity"
        XCTAssertTrue(makeOffer().shouldOffer())
        XCTAssertFalse(answered)
    }

    func testAlreadyDefaultComparesBundleIDNotPath() {
        // The registered handler is another copy of Undertone elsewhere on disk.
        system.appBundleURL = URL(fileURLWithPath: "/Users/someone/Downloads/Undertone.app")
        system.ownAll()
        XCTAssertFalse(makeOffer().shouldOffer())
    }

    func testForceOfferIgnoresSavedAnswer() {
        store.answered = true
        system.ownAll()
        XCTAssertTrue(makeOffer(force: true).shouldOffer())
    }

    // MARK: - Answering

    func testAcceptSetsAllFiveAndSavesAnswer() async throws {
        try await makeOffer().accept()
        XCTAssertEqual(system.setCalls.map(\.ext), ["mp3", "m4a", "flac", "aiff", "wav"])
        XCTAssertTrue(system.setCalls.allSatisfy { $0.appURL == system.appBundleURL })
        XCTAssertTrue(answered)
    }

    func testAcceptContinuesAfterOneFailure() async {
        system.failingExtensions = ["flac"]
        do {
            try await makeOffer().accept()
            XCTFail("accept() should report the failure")
        } catch {
            XCTAssertEqual(system.setCalls.map(\.ext), ["mp3", "m4a", "flac", "aiff", "wav"],
                           "the formats after the failing one are still attempted")
        }
    }

    func testAcceptFailureStillCountsAsAnswered() async {
        system.failingExtensions = ["mp3"]
        try? await makeOffer().accept()
        XCTAssertTrue(answered)
    }

    func testDeclineSavesAnswerAndSetsNothing() {
        makeOffer().decline()
        XCTAssertTrue(answered)
        XCTAssertTrue(system.setCalls.isEmpty)
        XCTAssertFalse(makeOffer().shouldOffer())
    }
}

@MainActor
final class DefaultPlayerOfferViewModelTests: XCTestCase {
    private var system: FakeSystem!
    private var store: MemoryStore!

    override func setUp() {
        super.setUp()
        system = FakeSystem()
        store = MemoryStore()
    }

    private func makeModel() -> NowPlayingViewModel {
        NowPlayingViewModel(defaultPlayer: DefaultPlayerOffer(system: system, store: store))
    }

    private var answered: Bool { store.answered }

    func testViewModelWithoutOfferShowsNoCard() {
        XCTAssertFalse(NowPlayingViewModel().showDefaultPlayerOffer)
    }

    func testViewModelShowsCardWhenOfferPending() {
        XCTAssertTrue(makeModel().showDefaultPlayerOffer)
    }

    func testDeclineHidesCardAndSavesAnswer() {
        let model = makeModel()
        model.declineDefaultPlayerOffer()
        XCTAssertFalse(model.showDefaultPlayerOffer)
        XCTAssertTrue(answered)
        XCTAssertTrue(system.setCalls.isEmpty)
    }

    func testAcceptHidesCardImmediately() {
        let model = makeModel()
        model.acceptDefaultPlayerOffer()
        XCTAssertFalse(model.showDefaultPlayerOffer, "the card goes away on the click, not when macOS finishes")
    }

    func testAcceptFailureShowsErrorBanner() async throws {
        system.failingExtensions = ["flac"]
        let model = makeModel()
        model.acceptDefaultPlayerOffer()
        for _ in 0..<200 where model.errorMessage == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains("Get Info"), "the banner should say how to do it by hand: \(message)")
    }

    func testOpeningFilesLeavesOfferPending() {
        let model = makeModel()
        model.handleOpenedFiles([URL(fileURLWithPath: "/tmp/not-audio.txt")])
        XCTAssertTrue(model.showDefaultPlayerOffer, "opening files is not an answer")
        XCTAssertFalse(answered)
    }
}
