import AppKit
import SwiftUI
import UndertoneCore

@MainActor
enum PreviewRenderer {
    /// Draws the popover offscreen with made-up content. It goes through a real
    /// hosting view rather than `ImageRenderer`, which cannot draw AppKit-backed
    /// controls (sliders, the queue list) and leaves placeholders in their place.
    static func render(to path: String, showDefaultPlayerOffer: Bool = false, queueOpen: Bool = false) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = NowPlayingViewModel()
        model.title = "Tomorrow isn't coming"
        model.artist = "LOCAL AUDIO · AIFF"
        model.duration = 168.5
        model.currentTime = 64
        model.isPlaying = true
        model.showDefaultPlayerOffer = showDefaultPlayerOffer
        if queueOpen {
            let names = ["Paper Lanterns", "Tomorrow isn't coming", "Low Tide", "Glass Morning"]
            model.queueItems = names.enumerated().map { i, name in
                QueueItem(index: i, url: URL(fileURLWithPath: "/demo/\(name).aiff"), name: name, isCurrent: i == 1)
            }
        }

        let host = NSHostingView(rootView: ContentView(viewModel: model, queueExpanded: queueOpen))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // A moment on the run loop lets the list load its rows before the snapshot. It has
        // to stay shorter than the view model's 0.25 s poll, which would otherwise replace
        // the made-up playback state with the (empty) real player's.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "Undertone.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render preview"])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Undertone.Preview", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: path))
        print("Preview saved: \(path)")
    }
}
