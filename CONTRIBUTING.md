# Contributing to Undertone

Thanks for your interest. Issues labeled
[good first issue](https://github.com/Qeetba/Undertone/labels/good%20first%20issue) and
[help wanted](https://github.com/Qeetba/Undertone/labels/help%20wanted) are the best places to start.
For anything larger, or anything that changes how the player looks or behaves, open an issue first so the
approach can be agreed on before you write code.

## What Undertone is for

Undertone plays the audio files you already have and otherwise stays out of the way. Changes need to keep
these promises:

- It lives in the menu bar only: no Dock icon, no windows, one small popover.
- It plays local files. No streaming services, accounts, library indexing, analytics or networking.
- It changes nothing on your Mac without being asked. The only system setting it touches is the default app
  for audio files, and only when **Make default** is clicked. The build script never installs anything.
- The popover stays uncluttered. A new feature should not need a new permanent control if an existing one
  can carry it; the waves, for example, are switched by the logo.
- It costs almost nothing while you are not looking at it. The waves only animate while the popover is open,
  and they follow the macOS Reduce Motion setting until you choose otherwise.
- Failures are shown in the popover, never swallowed.
- No third-party dependencies in the app. (`ffmpeg` is used only to generate test fixtures.)

A pull request that trades one of these away is unlikely to be merged.

## Build and test

You need macOS 14 or later and Swift 5.9 or later (Xcode 15 or later). No signing certificate is required;
builds are ad hoc signed.

```sh
swift build                          # debug build
swift test                           # unit tests; nothing is played
UNDERTONE_SMOKE_TEST=1 swift test    # also the tests that really play audio (silent files)
./build.sh                           # release build, assembled into dist/Undertone.app
open dist/Undertone.app
```

One smoke test checks each file format and is skipped unless its fixtures exist. `Scripts/generate-fixtures.sh`
creates them and needs `ffmpeg`.

`Scripts/release.sh` signs with a Developer ID certificate and notarizes the result. Only the maintainer
needs it.

The tests never change your default apps: the code that talks to Launch Services and to saved settings is
reached through small protocols, and the tests substitute fakes.

## Checking the popover by hand

Unit tests and `--render-preview` pictures say nothing about how the popover responds to the mouse, whether
its window takes the first click, or where it lands on screen. Bugs of all three kinds have shipped past
green tests. If your change touches any of that, run the app and try it:

- Open the popover fresh and make your first click or drag the thing you changed.
- Open and close the queue drawer, close the popover and reopen it, and check that it stays below the menu bar.
- Try the queue with one track and with enough tracks to scroll.

Two things to know when working on the popover:

- A SwiftUI `List` on macOS is an AppKit table that swallows clicks and drags meant for its rows. The queue
  rows are plain views for that reason.
- A plain button responds only where its label draws something. Give a label made of a word and an icon a
  content shape, or the gap between them is dead.

## Pull requests

- Changes reach `main` through pull requests.
- Pull requests are squash-merged, and the pull request's title and description become the commit message.
  Write them to stand alone: what changed and why.
- Keep each pull request to one change.
- Run `UNDERTONE_SMOKE_TEST=1 swift test` before you open it, and add or update tests for behavior you change.
- Say what you tested by hand, including the macOS version and whether the Mac is Apple silicon or Intel.
- Update the README when you change behavior it describes, and redo the screenshots when you change how the
  popover looks (the README's "Install and preview" section has the commands).

## Reporting bugs

Include your macOS version, your Mac's processor, and the steps that lead to the problem. For a file that
will not play or plays wrongly, say what format it is and how it was made, and quote the message in the
popover's error banner if there was one.
