import XCTest
@testable import UndertoneCore

/// The visualizer's ears: how much bass, mid and treble is in a stretch of audio.
@MainActor
final class AudioBandsTests: XCTestCase {

    private func sine(_ frequency: Double, amplitude: Float = 0.5, count: Int = 2048, sampleRate: Double = 44100) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    // MARK: - Splitting samples into bands

    func testSilenceHasNoEnergyInAnyBand() {
        let bands = AudioBands.measure([Float](repeating: 0, count: 2048), sampleRate: 44100)
        XCTAssertEqual(bands, .silent)
    }

    func testNoSamplesIsSilence() {
        XCTAssertEqual(AudioBands.measure([], sampleRate: 44100), .silent)
    }

    func testBassToneLandsInTheLowBand() {
        let bands = AudioBands.measure(sine(60), sampleRate: 44100)
        // RMS of a sine is amplitude / √2 ≈ 0.354 here.
        XCTAssertEqual(bands.low, 0.354, accuracy: 0.05)
        XCTAssertGreaterThan(bands.low, bands.mid * 4)
        XCTAssertLessThan(bands.high, 0.01)
    }

    func testMidToneLandsInTheMidBand() {
        let bands = AudioBands.measure(sine(800), sampleRate: 44100)
        XCTAssertEqual(bands.mid, 0.354, accuracy: 0.05)
        XCTAssertGreaterThan(bands.mid, bands.low * 4)
        XCTAssertGreaterThan(bands.mid, bands.high * 4)
    }

    func testTrebleToneLandsInTheHighBand() {
        let bands = AudioBands.measure(sine(9000), sampleRate: 44100)
        XCTAssertEqual(bands.high, 0.354, accuracy: 0.05)
        XCTAssertGreaterThan(bands.high, bands.mid * 4)
        XCTAssertLessThan(bands.low, 0.01)
    }

    func testBandsFollowTheSampleRate() {
        let bands = AudioBands.measure(sine(60, sampleRate: 96000), sampleRate: 96000)
        XCTAssertGreaterThan(bands.low, bands.mid * 4)
    }

    // MARK: - Reading bands out of a file at a playback position

    func testAnalyzerHearsTheToneInAFile() throws {
        let analyzer = try TrackAnalyzer(url: try toneWAV(frequency: 60))
        let bands = analyzer.bands(at: 0.3)
        XCTAssertEqual(bands.low, 0.354, accuracy: 0.05)
        XCTAssertGreaterThan(bands.low, bands.mid * 4)
    }

    func testAnalyzerHearsNothingInASilentFile() throws {
        let analyzer = try TrackAnalyzer(url: try silentWAV())
        XCTAssertEqual(analyzer.bands(at: 0.1), .silent)
    }

    func testAnalyzerIsSilentPastTheEndOfTheFile() throws {
        let analyzer = try TrackAnalyzer(url: try toneWAV(frequency: 60, seconds: 0.5))
        XCTAssertEqual(analyzer.bands(at: 30), .silent)
        XCTAssertEqual(analyzer.bands(at: -1), .silent)
    }

    func testAnalyzerGivesTheSameAnswerAfterJumpingAround() throws {
        let url = try toneWAV(frequency: 800)
        let fresh = try TrackAnalyzer(url: url).bands(at: 0.2)
        let analyzer = try TrackAnalyzer(url: url)
        _ = analyzer.bands(at: 0.6)
        _ = analyzer.bands(at: 0.61)
        let afterSeekingBack = analyzer.bands(at: 0.2)
        XCTAssertEqual(afterSeekingBack.mid, fresh.mid, accuracy: 0.001)
    }

    func testAnalyzerGivesTheSameAnswerWhenSteppingForwardFrameByFrame() throws {
        let url = try toneWAV(frequency: 800)
        let fresh = try TrackAnalyzer(url: url).bands(at: 0.3)
        let analyzer = try TrackAnalyzer(url: url)
        for step in 0...3 { _ = analyzer.bands(at: 0.2 + Double(step) / 30) }
        XCTAssertEqual(analyzer.bands(at: 0.3).mid, fresh.mid, accuracy: 0.001)
    }

    func testAnalyzerDoesNotHearASoundBeforeItPlays() throws {
        let analyzer = try TrackAnalyzer(url: try toneWAV(frequency: 800, startingAt: 0.5))
        XCTAssertLessThan(analyzer.bands(at: 0.47).mid, 0.01, "30 ms before the tone starts")
        XCTAssertGreaterThan(analyzer.bands(at: 0.53).mid, 0.2, "30 ms after it starts")
    }

    func testAnalyzerRejectsAFileThatIsNotAudio() {
        XCTAssertThrowsError(try TrackAnalyzer(url: URL(fileURLWithPath: "/nonexistent/undertone.wav")))
    }

    // MARK: - The player

    func testPlayerReportsSilenceWhileNotPlaying() throws {
        let player = PlayerController()
        player.open(urls: [try toneWAV(frequency: 60)], playImmediately: false)
        XCTAssertEqual(player.currentBands(), .silent)
    }

    func testPlayerReportsSilenceWithNothingLoaded() {
        XCTAssertEqual(PlayerController().currentBands(), .silent)
    }

    func testPlayerReportsTheBandsOfWhatIsPlaying() throws {
        guard ProcessInfo.processInfo.environment["UNDERTONE_SMOKE_TEST"] == "1" else {
            throw XCTSkip("Set UNDERTONE_SMOKE_TEST=1 for real playback")
        }
        let player = PlayerController()
        player.volume = 0
        player.open(urls: [try toneWAV(frequency: 60, seconds: 2)], playImmediately: true)
        XCTAssertTrue(SmokeTest.waitFor(seconds: 1) { player.currentTime > 0.1 })
        XCTAssertGreaterThan(player.currentBands().low, 0.2)
    }

    // MARK: - Smoothing for the eye

    func testDriveRisesQuicklyTowardLoudAudio() {
        var drive = WaveDrive()
        drive.update(toward: AudioBands(low: 0.4, mid: 0.4, high: 0.4), elapsed: 1.0 / 30)
        XCTAssertGreaterThan(drive.low, 0.4, "one frame is enough to see a beat land")
    }

    func testDriveFallsBackSlowly() {
        var drive = WaveDrive()
        for _ in 0..<30 { drive.update(toward: AudioBands(low: 0.4, mid: 0.4, high: 0.4), elapsed: 1.0 / 30) }
        let peak = drive.low
        drive.update(toward: .silent, elapsed: 1.0 / 30)
        XCTAssertGreaterThan(drive.low, peak * 0.7, "the fall is gentler than the rise")
        XCTAssertLessThan(drive.low, peak)
        for _ in 0..<90 { drive.update(toward: .silent, elapsed: 1.0 / 30) }
        XCTAssertLessThan(drive.low, 0.02, "and it does settle")
    }

    func testDriveStaysBetweenZeroAndOne() {
        var drive = WaveDrive()
        for _ in 0..<60 { drive.update(toward: AudioBands(low: 5, mid: 5, high: 5), elapsed: 1.0 / 30) }
        XCTAssertLessThanOrEqual(drive.low, 1)
        XCTAssertLessThanOrEqual(drive.high, 1)
        drive.update(toward: .silent, elapsed: 60)
        XCTAssertGreaterThanOrEqual(drive.low, 0)
    }

    func testQuietTrebleStillRegisters() {
        // Treble carries far less energy than bass in real music; the drive compensates.
        var bass = WaveDrive(), treble = WaveDrive()
        for _ in 0..<30 {
            bass.update(toward: AudioBands(low: 0.05, mid: 0, high: 0), elapsed: 1.0 / 30)
            treble.update(toward: AudioBands(low: 0, mid: 0, high: 0.05), elapsed: 1.0 / 30)
        }
        XCTAssertGreaterThan(treble.high, bass.low)
    }

    func testDriveCanStartAlreadySettled() {
        let drive = WaveDrive(settledOn: AudioBands(low: 0.2, mid: 0.1, high: 0.03))
        XCTAssertGreaterThan(drive.low, 0.3)
        XCTAssertGreaterThan(drive.mid, 0.2)
    }
}
