import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

public struct QueueItem: Identifiable, Equatable {
    /// The file itself identifies a row (the queue holds no duplicates), so a row
    /// keeps its identity when it is moved or when a row above it is removed.
    public var id: URL { url }
    /// Position in the queue right now.
    public let index: Int
    public let url: URL
    public let name: String
    public let isCurrent: Bool

    public init(index: Int, url: URL, name: String, isCurrent: Bool) {
        self.index = index
        self.url = url
        self.name = name
        self.isCurrent = isCurrent
    }
}

/// Observable view model bridging PlayerController to SwiftUI.
/// Runs on the main actor; polls playback position for the seek slider.
@MainActor
public final class NowPlayingViewModel: ObservableObject {
    public let player = PlayerController()

    @Published public var title = "No Track"
    @Published public var artist = ""
    @Published public var album = ""
    @Published public var artwork: NSImage?
    @Published public var isPlaying = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var volume: Float = 1.0
    @Published public var queueItems: [QueueItem] = []
    @Published public var currentIndex: Int?
    @Published public var errorMessage: String?
    @Published public var isScrubbing = false
    /// True while the first-run "make default player" card is waiting for an answer.
    @Published public var showDefaultPlayerOffer = false

    private var timer: Timer?
    private var metadataTask: Task<Void, Never>?
    private let defaultPlayer: DefaultPlayerOffer?

    /// - Parameter defaultPlayer: the first-run offer, or nil where there is nothing
    ///   to offer (tests, previews, the smoke test).
    public init(defaultPlayer: DefaultPlayerOffer? = nil) {
        self.defaultPlayer = defaultPlayer
        showDefaultPlayerOffer = defaultPlayer?.shouldOffer() ?? false
        player.onChange = { [weak self] in self?.refresh() }
        player.onTrackLoaded = { [weak self] in self?.loadMetadataForCurrentTrack() }
        player.onError = { [weak self] message in
            self?.errorMessage = message
            self?.refresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                self.currentTime = self.player.currentTime
                self.duration = self.player.duration
                self.isPlaying = self.player.isPlaying
            }
        }
    }

    deinit {
        timer?.invalidate()
        metadataTask?.cancel()
    }

    // MARK: - Opening files

    /// Entry point used by the file-open delegate (cold and warm launch) and the Open… panel.
    /// Replaces the queue and starts playing immediately.
    public func handleOpenedFiles(_ urls: [URL]) {
        let supported = SupportedAudio.filter(urls)
        guard !supported.isEmpty else {
            errorMessage = "No playable audio files in selection."
            return
        }
        errorMessage = nil
        player.open(urls: supported, playImmediately: true)
        refresh()
    }

    /// Shows an Open panel; the picked files replace the queue and play.
    public func openFilesPanel() {
        if let urls = pickAudioFiles() { handleOpenedFiles(urls) }
    }

    /// Shows an Open panel; the picked files join the end of the queue.
    public func addToQueuePanel() {
        if let urls = pickAudioFiles() { addToQueue(urls) }
    }

    private func pickAudioFiles() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = nil
        panel.allowedContentTypes = [.audio]
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }

    // MARK: - Editing the queue

    /// Adds files after everything already queued. What is playing keeps playing.
    public func addToQueue(_ urls: [URL]) {
        let supported = SupportedAudio.filter(urls)
        guard !supported.isEmpty else {
            errorMessage = "No playable audio files in selection."
            return
        }
        errorMessage = nil
        player.enqueue(urls: supported)
        refresh()
    }

    public func removeFromQueue(at index: Int) { player.removeTrack(at: index); refresh() }

    /// Drag-to-reorder; the arguments are exactly what SwiftUI's `onMove` hands over.
    public func moveQueueItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        player.moveTracks(fromOffsets: source, toOffset: destination)
        refresh()
    }

    public func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Transport

    public func togglePlay() { player.togglePlay(); refresh() }
    public func next() { player.nextTrack(); refresh() }
    public func previous() { player.previousTrack(); refresh() }
    public func selectTrack(_ index: Int) { player.selectTrack(index); refresh() }
    public func seek(to time: Double) {
        isScrubbing = false
        player.seek(to: time)
        currentTime = player.currentTime
    }

    public func setVolume(_ v: Float) {
        volume = v
        player.volume = v
    }

    public func dismissError() { errorMessage = nil }

    // MARK: - First-run default player offer

    /// "Make default": the card goes away on the click; a failure lands in the error banner.
    public func acceptDefaultPlayerOffer() {
        guard let defaultPlayer, showDefaultPlayerOffer else { return }
        showDefaultPlayerOffer = false
        Task { [weak self] in
            do {
                try await defaultPlayer.accept()
            } catch {
                self?.errorMessage = "Couldn't make Undertone the default player. In Finder, choose Get Info on a music file, then Open with → Change All."
            }
        }
    }

    /// "Not now": never asked again.
    public func declineDefaultPlayerOffer() {
        defaultPlayer?.decline()
        showDefaultPlayerOffer = false
    }

    // MARK: - State refresh

    private func refresh() {
        if player.currentURL == nil {
            metadataTask?.cancel()
            title = "No Track"
            artist = ""
            album = ""
            artwork = nil
        }
        isPlaying = player.isPlaying
        duration = player.duration
        if !isScrubbing {
            currentTime = player.currentTime
        }
        currentIndex = player.playlist.currentIndex
        let items = player.playlist.items
        queueItems = items.enumerated().map { i, url in
            QueueItem(index: i, url: url, name: url.deletingPathExtension().lastPathComponent, isCurrent: i == currentIndex)
        }
    }

    private func loadMetadataForCurrentTrack() {
        guard let url = player.currentURL else {
            title = "No Track"; artist = ""; album = ""; artwork = nil
            return
        }
        let fallbackName = url.deletingPathExtension().lastPathComponent
        title = fallbackName
        artist = ""
        album = ""
        artwork = nil
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            let meta = await MetadataLoader.load(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.player.currentURL == url else { return }
                self?.title = MetadataLoader.displayName(for: url, title: meta.title)
                self?.artist = meta.artist ?? ""
                self?.album = meta.album ?? ""
                if let data = meta.artwork, let image = NSImage(data: data) {
                    self?.artwork = image
                }
            }
        }
    }
}

// MARK: - Formatting

public extension TimeInterval {
    /// Formats seconds as m:ss.
    var asClockString: String {
        let t = max(0, self)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
