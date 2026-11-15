import AVFoundation
import Foundation

/// AVAudioPlayer-backed playback engine: load, play/pause, seek, volume,
/// multi-file queue with next/previous and auto-advance on completion.
/// All failures are reported through `onError` so the UI can show them.
public final class PlayerController: NSObject {
    private var player: AVAudioPlayer?
    public private(set) var playlist = Playlist()

    /// Called whenever playback state (playing/track/currentTime) changes.
    public var onChange: (() -> Void)?
    /// Called with a human-readable error message whenever something fails.
    public var onError: ((String) -> Void)?
    /// Called right after a new track is successfully loaded.
    public var onTrackLoaded: (() -> Void)?

    /// Playback volume, 0.0 ... 1.0. Applies to the current and every subsequent track.
    public var volume: Float {
        get { player?.volume ?? storedVolume }
        set {
            storedVolume = min(max(newValue, 0), 1)
            player?.volume = storedVolume
        }
    }
    private var storedVolume: Float = 1.0

    public private(set) var isPlaying = false

    public var currentURL: URL? { playlist.current }

    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }

    // MARK: - Visualizer

    /// Opened on first use, so nothing is decoded twice unless something is watching.
    private var analyzer: TrackAnalyzer?
    private var analysisUnavailable = false

    /// The bass, mid and treble levels of the audio being played right now.
    /// Silent while paused, with nothing loaded, or for a file that cannot be analyzed.
    public func currentBands() -> AudioBands {
        guard isPlaying, let player, let url = currentURL else { return .silent }
        if analyzer == nil, !analysisUnavailable {
            analyzer = try? TrackAnalyzer(url: url)
            analysisUnavailable = analyzer == nil
        }
        return analyzer?.bands(at: player.currentTime) ?? .silent
    }

    // MARK: - Queue control

    /// Replaces the queue with the given files and (optionally) starts playing the first one.
    /// An empty array clears playback. An entirely unsupported selection preserves it.
    public func open(urls: [URL], playImmediately: Bool) {
        let supported = SupportedAudio.filter(urls)
        guard urls.isEmpty || !supported.isEmpty else {
            onError?("No supported audio files could be queued.")
            return
        }
        playlist.replaceAll(with: supported)
        loadCurrent(autoplay: playImmediately)
    }

    /// Adds files to the end of the queue without touching what is playing.
    /// Adding to an empty queue starts playing the first file.
    public func enqueue(urls: [URL]) {
        let supported = SupportedAudio.filter(urls)
        guard !supported.isEmpty else {
            onError?("No supported audio files could be queued.")
            return
        }
        let wasEmpty = playlist.isEmpty
        playlist.append(supported)
        if wasEmpty {
            loadCurrent(autoplay: true)
        } else {
            onChange?()
        }
    }

    /// Removes one track from the queue. Removing the current track moves on to the one
    /// that followed it, still playing if it was playing; with nothing following, playback
    /// stops on the last remaining track. Removing any other track leaves playback alone.
    public func removeTrack(at index: Int) {
        let keepPlaying = isPlaying && index + 1 < playlist.count
        if playlist.remove(at: index) {
            loadCurrent(autoplay: keepPlaying)
        } else {
            onChange?()
        }
    }

    /// Reorders the queue (same contract as SwiftUI's `onMove`). Playback is untouched.
    public func moveTracks(fromOffsets source: IndexSet, toOffset destination: Int) {
        playlist.move(fromOffsets: source, toOffset: destination)
        onChange?()
    }

    public func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    public func play() {
        guard let player else { return }
        if player.play() {
            isPlaying = true
            onChange?()
        } else {
            onError?("Playback failed to start.")
        }
    }

    public func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        onChange?()
    }

    /// Jumps to an absolute time (seconds) in the current track.
    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), max(player.duration - 0.05, 0))
        player.currentTime = clamped
        onChange?()
    }

    /// Next track. At the end of the queue this is a no-op.
    public func nextTrack() {
        if playlist.advance() != nil {
            loadCurrent(autoplay: true)
        } else {
            onChange?()
        }
    }

    /// Previous track; if already on the first track, restarts it from the beginning.
    public func previousTrack() {
        if playlist.rewind() == nil {
            seek(to: 0)
        }
        loadCurrent(autoplay: true)
    }

    /// Selects a specific queue index and plays it.
    public func selectTrack(_ index: Int) {
        if playlist.select(index) != nil {
            loadCurrent(autoplay: true)
        }
    }

    // MARK: - Loading

    private func loadCurrent(autoplay: Bool) {
        if let existing = player {
            existing.stop()
            self.player = nil
        }
        isPlaying = false
        analyzer = nil
        analysisUnavailable = false

        // Iterative recovery avoids recursion for a queue of unreadable files.
        while let url = playlist.current {
            do {
                let newPlayer = try AVAudioPlayer(contentsOf: url)
                newPlayer.delegate = self
                newPlayer.volume = storedVolume
                guard newPlayer.prepareToPlay() else {
                    throw NSError(domain: "Undertone.Playback", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Audio decoder could not prepare this file."])
                }
                player = newPlayer
                onTrackLoaded?()
                onChange?()
                if autoplay { play() }
                return
            } catch {
                onError?("Could not load \"\(url.lastPathComponent)\": \(error.localizedDescription)")
                playlist.dropCurrent()
            }
        }
        onChange?()
    }
}

extension PlayerController: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player === player else { return }
            if !flag { self.onError?("Playback ended with a decoding error.") }
            self.finishCurrentTrack()
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player === player else { return }
            self.onError?("Could not decode audio: \(error?.localizedDescription ?? "Unknown error")")
            self.finishCurrentTrack()
        }
    }

    private func finishCurrentTrack() {
        if playlist.advance() != nil {
            loadCurrent(autoplay: true)
        } else {
            player?.stop()
            isPlaying = false
            onChange?()
        }
    }
}
