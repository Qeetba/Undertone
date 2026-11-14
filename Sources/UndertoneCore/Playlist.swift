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
        guard let idx = index, items.indices.contains(idx) else { return nil }
        items.remove(at: idx)
        if items.isEmpty {
            index = nil
        } else if idx >= items.count {
            index = items.count - 1
        } else {
            index = idx
        }
        return current
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
