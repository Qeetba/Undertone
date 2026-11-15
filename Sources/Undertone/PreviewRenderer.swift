import AppKit
import SwiftUI
import UndertoneCore

@MainActor
enum PreviewRenderer {
    static func render(to path: String, showDefaultPlayerOffer: Bool = false) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = NowPlayingViewModel()
        model.title = "Tomorrow isn't coming"
        model.artist = "LOCAL AUDIO · AIFF"
        model.duration = 168.5
        model.currentTime = 64
        model.isPlaying = true
        model.showDefaultPlayerOffer = showDefaultPlayerOffer
        let renderer = ImageRenderer(content: ContentView(viewModel: model))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw NSError(domain: "Undertone.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render preview"])
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Undertone.Preview", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: path))
        print("Preview saved: \(path)")
    }
}
