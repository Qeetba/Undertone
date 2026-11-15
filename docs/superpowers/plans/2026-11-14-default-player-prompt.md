# First-Run Default Player Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On first launch, Undertone opens its popover with a card offering to become the default player for MP3, M4A, FLAC, AIFF and WAV, and never asks again once answered.

**Architecture:** A `DefaultPlayerOffer` type in `UndertoneCore` owns the decision, the saved answer and the "set default" action, talking to macOS through a `DefaultAppSystem` protocol so tests can fake it. `NowPlayingViewModel` publishes whether the card shows; `ContentView` draws it; `AppDelegate` opens the popover when it is pending.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit (`NSWorkspace`, `NSPopover`), SwiftUI, `UniformTypeIdentifiers`, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-14-default-player-prompt-design.md`

## Global Constraints

- macOS 14+, no new dependencies.
- Formats claimed, exactly: `mp3`, `m4a`, `flac`, `aiff`, `wav`.
- Card headline, exactly: `Make Undertone your default player for music files?`
- Buttons, exactly: `Not now` and `Make default`.
- No default is changed without a click on **Make default**.
- The card is never modal and never blocks playback.
- `build.sh` behaviour is unchanged.
- Saved-answer key: `defaultPlayerPromptAnswered` (Bool) in `UserDefaults.standard`, reached through `UserDefaultsAnswerStore` so tests can keep the answer in memory.

## Review Focus

1. Two copies of the app on disk: "already the default" must compare bundle identifiers, not paths. → Task 1 test `testAlreadyDefaultComparesBundleIDNotPath`.
2. Setting one format fails part-way: the remaining formats are still attempted and the error is reported. → Task 1 test `testAcceptContinuesAfterOneFailure`.
3. A song is opened from Finder while the card is pending: the card stays, playback is untouched. → Task 2 test `testOpeningFilesLeavesOfferPending`.
4. The saved answer survives a failed attempt, so the user is not asked again. → Task 1 test `testAcceptFailureStillCountsAsAnswered`.
5. Popover auto-open before the status item has a window: must not crash or show a detached popover. → Task 3, guard in `AppDelegate` (manual check; no unit test reaches AppKit).

---

### Task 1: `DefaultPlayerOffer` in UndertoneCore

**Files:**
- Create: `Sources/UndertoneCore/DefaultPlayerOffer.swift`
- Test: `Tests/UndertoneTests/DefaultPlayerOfferTests.swift`

**Interfaces — Produces:**

```swift
public protocol DefaultAppSystem {
    var appBundleURL: URL? { get }      // nil unless running from an .app bundle
    var appBundleID: String? { get }
    func defaultAppBundleID(for type: UTType) -> String?
    func setDefaultApp(at appURL: URL, for type: UTType) async throws
}
public struct WorkspaceDefaultAppSystem: DefaultAppSystem { public init() }

public protocol DefaultPlayerAnswerStore: AnyObject { var answered: Bool { get set } }
public final class UserDefaultsAnswerStore: DefaultPlayerAnswerStore { public init(_ defaults: UserDefaults = .standard) }

@MainActor public final class DefaultPlayerOffer {
    public static let extensions = ["mp3", "m4a", "flac", "aiff", "wav"]
    public static let launchArgument = "--offer-default-player"
    public init(system: DefaultAppSystem, store: DefaultPlayerAnswerStore, forceOffer: Bool = false)
    public func shouldOffer() -> Bool
    public func accept() async throws
    public func decline()
}
```

- [ ] **Step 1: Write failing tests** with a `FakeSystem` and an in-memory `DefaultPlayerAnswerStore` (a per-test `UserDefaults` suite leaves an empty plist in `~/Library/Preferences` on every run):
  - `testOffersOnFirstRunFromBundle` — bundle set, nothing saved, defaults owned by `com.apple.Music` → `true`.
  - `testSkipsOnceAnswered` — key `true` → `false`.
  - `testSkipsWithoutBundle` — `appBundleURL == nil` → `false`, key not saved.
  - `testSkipsWhileTranslocated` — URL containing `/AppTranslocation/` → `false`, key not saved.
  - `testAlreadyDefaultSavesAnswerAndSkips` — all five owned by the app's bundle ID → `false`, key saved `true`.
  - `testPartlyDefaultStillOffers` — four of five owned → `true`.
  - `testAlreadyDefaultComparesBundleIDNotPath` — handler has the app's bundle ID though the app lives at another path → `false`.
  - `testForceOfferIgnoresSavedAnswer` — key `true`, `forceOffer: true` → `true`.
  - `testAcceptSetsAllFiveAndSavesAnswer` — five `setDefaultApp` calls with the app URL; key `true`.
  - `testAcceptContinuesAfterOneFailure` — fake throws for `flac`; still five attempts; `accept()` throws.
  - `testAcceptFailureStillCountsAsAnswered` — after the throw, key is `true`.
  - `testDeclineSavesAnswerAndSetsNothing`.
- [ ] **Step 2:** Run `swift test --filter DefaultPlayerOfferTests`. Expected: compile failure, type not found.
- [ ] **Step 3:** Implement the file. `shouldOffer()` order: force → answered → bundle → translocation → already-default (saves the answer). `WorkspaceDefaultAppSystem` uses `NSWorkspace.shared.urlForApplication(toOpen:)` and the async `setDefaultApplication(at:toOpen:)`; `appBundleURL` is `Bundle.main.bundleURL` only when its extension is `app`. Types come from `UTType(filenameExtension:)`; an extension with no type is skipped.
- [ ] **Step 4:** Run `swift test --filter DefaultPlayerOfferTests`. Expected: 12 pass.

### Task 2: View model wiring

**Files:**
- Modify: `Sources/UndertoneCore/NowPlayingViewModel.swift`
- Test: `Tests/UndertoneTests/DefaultPlayerOfferTests.swift` (same file, second test class)

**Interfaces — Produces:**

```swift
public init(defaultPlayer: DefaultPlayerOffer? = nil)   // replaces init()
@Published public var showDefaultPlayerOffer: Bool
public func acceptDefaultPlayerOffer()
public func declineDefaultPlayerOffer()
```

- [ ] **Step 1: Write failing tests:**
  - `testViewModelWithoutOfferShowsNoCard` — `NowPlayingViewModel()` → `false`.
  - `testViewModelShowsCardWhenOfferPending` → `true`.
  - `testDeclineHidesCardAndSavesAnswer`.
  - `testAcceptHidesCardImmediately` — `false` straight after the call, before the async work finishes.
  - `testAcceptFailureShowsErrorBanner` — fake throws; `errorMessage` becomes non-nil and mentions `Get Info`.
  - `testOpeningFilesLeavesOfferPending` — `handleOpenedFiles([URL(fileURLWithPath: "/tmp/x.txt")])` leaves `showDefaultPlayerOffer == true`.
- [ ] **Step 2:** Run the filter. Expected: compile failure.
- [ ] **Step 3:** Implement. Error copy, exactly: `Couldn't make Undertone the default player. In Finder, choose Get Info on a music file, then Open with → Change All.`
- [ ] **Step 4:** Run `swift test`. Expected: all pass, existing tests included.

### Task 3: Card, auto-open, preview flag, README

**Files:**
- Modify: `Sources/Undertone/ContentView.swift` (card between the header row and the track row)
- Modify: `Sources/Undertone/AppDelegate.swift` (build the offer; open the popover when pending)
- Modify: `Sources/Undertone/PreviewRenderer.swift`, `Sources/Undertone/main.swift` (flag)
- Modify: `README.md`

**Interfaces — Consumes:** Task 1 and Task 2 signatures above.

- [ ] **Step 1:** Add the card to `ContentView`, shown when `viewModel.showDefaultPlayerOffer`. Headline and button labels from Global Constraints; sub-line `MP3, M4A, FLAC, AIFF and WAV files will open here.` Style: mint-tinted rounded panel like the error banner; **Make default** is a mint capsule, **Not now** is plain text.
- [ ] **Step 2:** `AppDelegate` creates `NowPlayingViewModel(defaultPlayer: DefaultPlayerOffer(system: WorkspaceDefaultAppSystem(), store: UserDefaultsAnswerStore(), forceOffer: <flag>))`. After the status item exists, if the card is pending, activate the app and show the popover once the button has a window (retry briefly; give up silently).
- [ ] **Step 3:** Launch flag `--offer-default-player`: forces the card for one session in the live app, and makes `--render-preview` draw the card.
- [ ] **Step 4:** README: describe the prompt, the flag, and correct the "default-app changes are manual" sentence.
- [ ] **Step 5: Verify.** `swift test` all pass; `./build.sh`; `Undertone --render-preview <png> --offer-default-player` and look at the PNG; launch `dist/Undertone.app` with the flag and confirm the popover window is on screen.
