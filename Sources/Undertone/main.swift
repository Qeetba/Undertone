import AppKit
import UndertoneCore

// Undertone — menu-bar-only audio player.
// Supports --smoke-test for headless real-playback verification.
if CommandLine.arguments.contains("--smoke-test") {
    let code = SmokeTest.run()
    exit(code)
}

if let index = CommandLine.arguments.firstIndex(of: "--render-preview") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: Undertone --render-preview /path/to/preview.png\n", stderr)
        exit(2)
    }
    do {
        try MainActor.assumeIsolated {
            try PreviewRenderer.render(to: CommandLine.arguments[index + 1])
        }
        exit(0)
    } catch {
        fputs("Preview failed: \(error)\n", stderr)
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon, no main window
    app.run()
}
