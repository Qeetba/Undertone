import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UndertoneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let viewModel = NowPlayingViewModel(defaultPlayer: DefaultPlayerOffer(
        system: WorkspaceDefaultAppSystem(),
        store: UserDefaultsAnswerStore(),
        forceOffer: CommandLine.arguments.contains(DefaultPlayerOffer.launchArgument)
    ))
    let popover = NSPopover()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no windows.
        NSApp.setActivationPolicy(.accessory)

        let content = NSHostingController(rootView: ContentView(viewModel: viewModel))
        // Report the SwiftUI content's size to the popover as it changes (the queue
        // drawer opening, rows being added). Without this the popover keeps the size it
        // first measured, and the next time it opens it is placed for that stale size:
        // a taller popover then hangs off the top of the screen.
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self
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

        // First run: drop the popover open so the offer is seen, and so a new
        // user learns where a menu-bar-only app lives.
        if viewModel.showDefaultPlayerOffer {
            showOfferPopover(attemptsLeft: 20)
        }
    }

    /// The status item needs a moment to land in the menu bar before a popover
    /// can anchor to it. Retries briefly, then gives up; the card is still there
    /// whenever the user opens the popover themselves.
    private func showOfferPopover(attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.viewModel.showDefaultPlayerOffer, !self.popover.isShown else { return }
            guard self.statusItem?.button?.window != nil else {
                if attemptsLeft > 0 { self.showOfferPopover(attemptsLeft: attemptsLeft - 1) }
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            self.showPopover()
        }
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
        // Clicking a status item does not activate a menu-bar app, so the popover would
        // open in a window that is not key. The first click or drag on a queue row in
        // such a window only activates it and is otherwise lost.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) {
        viewModel.isPopoverVisible = true
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.isPopoverVisible = false
    }
}
