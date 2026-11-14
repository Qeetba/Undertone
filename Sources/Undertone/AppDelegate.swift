import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UndertoneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = NowPlayingViewModel()
    let popover = NSPopover()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no windows.
        NSApp.setActivationPolicy(.accessory)

        let content = NSHostingController(rootView: ContentView(viewModel: viewModel))
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        // Force the dark polished look regardless of system appearance.
        popover.appearance = NSAppearance(named: .darkAqua)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Undertone")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    // MARK: - File open (cold + warm launch) plays immediately

    func application(_ application: NSApplication, open urls: [URL]) {
        viewModel.handleOpenedFiles(urls)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false // document-less app; files arrive via open-URLs events
    }

    // MARK: - Popover

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
