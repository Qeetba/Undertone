import Foundation

/// Pure queue/playlist logic, independent of AVFoundation, so it is trivially unit-testable.
public struct Playlist: Equatable {
    public private(set) var items: [URL] = []
    public private(set) var index: Int?

    public init() {}

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    /// The URL of the currently selected track, if any.
    public var current: URL? {
        guard let index, items.indices.contains(index) else { return nil }
        return items[index]
    }

    public var currentIndex: Int? { index }

    /// Appends URLs, skipping duplicates of URLs already queued.
    public mutating func append(_ urls: [URL]) {
        var existing = Set(items.map(\.absoluteString))
        for url in urls where existing.insert(url.absoluteString).inserted {
            items.append(url)
        }
        if index == nil, !items.isEmpty { index = 0 }
    }

    public mutating func replaceAll(with urls: [URL]) {
        items = []
        index = nil
        append(urls)
    }

    public mutating func clear() {
        items = []
        index = nil
    }

    /// Advances to the next track. Returns the new current URL, or nil at the end of the queue.
    @discardableResult
    public mutating func advance() -> URL? {
        guard let index, index + 1 < items.count else { return nil }
        self.index = index + 1
        return current
    }

    /// Goes back one track. Returns the new current URL, or nil if already at the first track.
    @discardableResult
    public mutating func rewind() -> URL? {
        guard let index, index > 0 else { return nil }
        self.index = index - 1
        return current
    }

    /// Selects a track by index. Returns the new current URL, or nil if out of range.
    @discardableResult
    public mutating func select(_ i: Int) -> URL? {
        guard items.indices.contains(i) else { return nil }
        index = i
        return current
    }

    /// Removes the current item (e.g. because it failed to load). The selection moves
    /// to the item that follows it, or to the last remaining item; nil if the queue is empty.
    @discardableResult
    public mutating func dropCurrent() -> URL? {
        guard let index else { return nil }
        remove(at: index)
        return current
    }

    /// Removes the item at `i`. Any other track that was current stays current. If the
    /// current track is the one removed, the selection moves to the item that followed it,
    /// or to the last remaining item. Returns true when the current track was the one removed.
    @discardableResult
    public mutating func remove(at i: Int) -> Bool {
        guard items.indices.contains(i) else { return false }
        let removedCurrent = i == index
        items.remove(at: i)
        if let index, i < index {
            self.index = index - 1
        } else if removedCurrent {
            index = items.isEmpty ? nil : min(i, items.count - 1)
        }
        return removedCurrent
    }

    /// Moves the items at `source` so they sit before the item currently at `destination`
    /// (`count` means the end), keeping their relative order. The current track stays
    /// current wherever it lands. Same contract as SwiftUI's `onMove`.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard source.allSatisfy(items.indices.contains), (0...items.count).contains(destination) else { return }
        let playing = current
        let moving = source.map { items[$0] }
        let insertion = destination - source.count(in: 0..<destination)
        for i in source.reversed() { items.remove(at: i) }
        items.insert(contentsOf: moving, at: insertion)
        // URLs are unique in the queue, so the playing track can be found again by URL.
        if let playing { index = items.firstIndex(of: playing) }
    }
}

/// Supported audio file extensions (MP3, M4A, FLAC, WAV plus close cousins AVAudioPlayer handles).
public enum SupportedAudio {
    public static let extensions: Set<String> = [
        "mp3", "m4a", "m4b", "m4p", "flac", "wav", "wave", "aiff", "aif", "aifc", "caf", "aac"
    ]

    public static func filter(_ urls: [URL]) -> [URL] {
        urls.filter { extensions.contains($0.pathExtension.lowercased()) }
    }
}
