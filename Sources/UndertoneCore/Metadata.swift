import AVFoundation
import Foundation

public struct TrackMetadata: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var artwork: Data?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, artwork: Data? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
    }
}

public enum MetadataLoader {
    /// Loads title/artist/album/artwork for an audio file using the modern async AVAsset API.
    /// Never throws; missing fields come back as nil.
    public static func load(for url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else {
            return TrackMetadata()
        }

        var meta = TrackMetadata()
        for item in items {
            // commonKey/stringValue/dataValue are synchronous properties on
            // AVMetadataItem (only the asset-level metadata fetch is async).
            switch item.commonKey {
            case .commonKeyTitle:
                meta.title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                meta.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                meta.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                if let data = try? await item.load(.dataValue) {
                    meta.artwork = data
                }
            default:
                break
            }
        }
        return meta
    }

    /// A friendly display name: embedded title if present, otherwise the file name.
    public static func displayName(for url: URL, title: String?) -> String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            return title
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
