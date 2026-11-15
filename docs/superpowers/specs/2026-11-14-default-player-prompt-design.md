# First-run "make default player" prompt — design

Date: 2026-11-14. Size: a small change.

## Intent

People who receive Undertone should be offered, once, the chance to make it
their default player for music files. Today that takes a per-format trip
through Finder's Get Info. Because Undertone is menu-bar-only, the same moment
also shows a new user where the app lives.

## Goals

- On first launch, the popover opens by itself and shows a card asking
  "Make Undertone your default player for music files?" with **Not now** and
  **Make default**.
- **Make default** sets Undertone as the default app for MP3, M4A, FLAC, AIFF
  and WAV, then the card goes away.
- **Not now** dismisses the card.
- Once answered either way, the app never asks again.

- A launch argument, `--offer-default-player`, makes the card appear again
  for that one launch, whatever answer was saved (added by Keith after
  approval).

## Non-goals

- No settings screen and no in-app "make default" button. The launch
  argument above and Finder's Get Info cover anyone who changes their mind.
- No change to the other formats the app can open (AAC, M4B, CAF).
- `build.sh` still never installs anything or changes defaults; only the
  running app does, and only when the user clicks **Make default**.

## Anti-goals

- Changing any default without a click on **Make default**.
- Asking a second time, on any later launch.
- Interrupting playback: the card must not be modal or block a song that was
  opened from Finder.

## Approaches

1. **System alert at launch.** Smallest change and impossible to miss, but it
   is a stock dialog, sits on top of music that is starting, and does not
   show where the app lives.
2. **Card in the popover, which opens itself on first launch.** Chosen. Shows
   the user where Undertone lives, matches the app's look, does not block
   playback. Costs a new card in the view and state in the view model.
3. **Never ask, only offer a button.** Dropped: it does not ask.

Keith picked approach 2.

## Design

- **Remembering the answer:** one saved Boolean in the app's `UserDefaults`,
  set when either button is clicked. This is the app's first saved preference.
- **When the card is offered** (all must hold):
  - no answer has been saved;
  - the app is running from an `.app` bundle (not `swift run`);
  - Undertone is not already the default for all five formats;
  - macOS is not running the app from a temporary quarantine location
    (App Translocation), where a default would point at a path that vanishes.
- **Where the logic lives:** the "should we offer" decision and the list of
  five formats go in `UndertoneCore`, with the system calls (read current
  default, set default) behind a small protocol so tests can fake them.
  `NowPlayingViewModel` publishes whether the card shows and exposes accept
  and decline actions. `ContentView` draws the card. `AppDelegate` opens the
  popover after launch when the card is pending.
- **The card stays** until one of its buttons is clicked. Closing the popover
  by clicking elsewhere is not an answer.
- **If setting the default fails,** the existing error banner says so and
  points at Finder's Get Info. The answer still counts as given.
- **README:** replace the "default-app changes are manual" wording and
  describe the prompt.

## Calls made by Claude, not Keith

- The card persists until answered, rather than counting "shown" as "asked".
- If Undertone already owns all five formats, the answer is saved as given, so
  a user who later moves a format elsewhere is not asked.
- The App Translocation guard. It cannot be exercised on this machine.
- A failed attempt is not retried on the next launch.

## Left to the builder

- Card wording beyond the headline, and its exact styling within the
  existing palette.
- How to show the card for verification without touching system defaults
  (for example an option on `--render-preview`).
- Unit tests: the offer decision, and accept/decline against a fake system
  and an isolated `UserDefaults` suite.
