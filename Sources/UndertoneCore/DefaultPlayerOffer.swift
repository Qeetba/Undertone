import AppKit
import Foundation
import UniformTypeIdentifiers

/// The slice of Launch Services the first-run offer needs, so tests can fake it.
public protocol DefaultAppSystem {
    /// Where the running app's bundle lives, or nil when not running from an `.app`
    /// (for example `swift run`), in which case macOS has nothing to register.
    var appBundleURL: URL? { get }
    var appBundleID: String? { get }
    /// Bundle identifier of the app currently set to open `type`.
    func defaultAppBundleID(for type: UTType) -> String?
    func setDefaultApp(at appURL: URL, for type: UTType) async throws
}

public struct WorkspaceDefaultAppSystem: DefaultAppSystem {
    public init() {}

    public var appBundleURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    public var appBundleID: String? { Bundle.main.bundleIdentifier }

    public func defaultAppBundleID(for type: UTType) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    public func setDefaultApp(at appURL: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
    }
}

/// Where the "already answered" flag is kept: `UserDefaults` in the app, memory in tests.
public protocol DefaultPlayerAnswerStore: AnyObject {
    var answered: Bool { get set }
}

public final class UserDefaultsAnswerStore: DefaultPlayerAnswerStore {
    public static let key = "defaultPlayerPromptAnswered"
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var answered: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Decides whether to offer "make Undertone the default player", remembers the
/// answer, and carries it out. Asked once: either answer is saved for good.
@MainActor
public final class DefaultPlayerOffer {
    /// The formats Undertone claims when the user accepts.
    public static let extensions = ["mp3", "m4a", "flac", "aiff", "wav"]
    /// Launch argument that makes the offer appear again for one launch.
    public static let launchArgument = "--offer-default-player"

    private let system: DefaultAppSystem
    private let store: DefaultPlayerAnswerStore
    private let forceOffer: Bool

    /// - Parameter forceOffer: show the offer for this launch whatever was saved
    ///   (the `--offer-default-player` launch argument).
    public init(system: DefaultAppSystem, store: DefaultPlayerAnswerStore, forceOffer: Bool = false) {
        self.system = system
        self.store = store
        self.forceOffer = forceOffer
    }

    private var types: [UTType] {
        Self.extensions.compactMap { UTType(filenameExtension: $0) }
    }

    public func shouldOffer() -> Bool {
        if forceOffer { return true }
        if store.answered { return false }
        guard let appURL = system.appBundleURL, let appID = system.appBundleID else { return false }
        // A freshly downloaded app can be run by macOS from a temporary read-only
        // copy. A default set now would point at a path that disappears; ask later.
        if appURL.path.contains("/AppTranslocation/") { return false }
        if types.allSatisfy({ system.defaultAppBundleID(for: $0) == appID }) {
            markAnswered() // nothing to ask, now or later
            return false
        }
        return true
    }

    /// Claims every format. Tries all of them even if one fails, then reports the
    /// first failure. The answer counts as given either way.
    public func accept() async throws {
        markAnswered()
        guard let appURL = system.appBundleURL else { return }
        var firstError: Error?
        for type in types {
            do {
                try await system.setDefaultApp(at: appURL, for: type)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    public func decline() {
        markAnswered()
    }

    private func markAnswered() {
        store.answered = true
    }
}
