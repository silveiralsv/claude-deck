# Claude Deck

A macOS menu bar app (SwiftUI, Swift Package, no Xcode project) that shows the running Claude Code sessions as cards, with a pixel Clawd per session. README.md explains where each piece of data comes from.

## Commands

- Build: `./build.sh` (writes `ClaudeDeck.app`)
- Relaunch the development build after a build: `pkill -x ClaudeDeck; open ClaudeDeck.app` (this quits any copy, including one in `/Applications`). To install for real, follow INSTALL.md.
- Tests: `scripts/test.sh`
- Performance: `scripts/perf-load.sh [app ...]` (fixed load, the main A/B check), `scripts/perf.sh [samples]` and `scripts/perf.sh profile` (your real sessions)

## Measure performance before every commit and push

The deck runs all day, so a change that costs CPU or memory is a regression even when it works. Before you commit or push a change to app code:

1. Run `scripts/perf-load.sh <build before> <build after>` (keep a copy of the old `ClaudeDeck.app` before you rebuild). It runs each build on 9 made-up sessions under a fake HOME and measures CPU and memory with 0, 3, 6 and 9 of them working. It doesn't depend on your real sessions, so its numbers are comparable from run to run, and your own deck can stay open. Then do the checks below with `scripts/perf.sh` on your real sessions.
2. Keep the deck window open (Show deck) for every measurement. A closed window doesn't draw and shows nothing.
3. With the build from before your change running, run `scripts/perf.sh`. This is the baseline.
4. Build and relaunch your change, wait about 10 seconds, and run `scripts/perf.sh` again.
5. Compare the runs only when their `sessions` lines match. Busy sessions animate their pet, so more busy sessions means more CPU.
6. Measure back to back. The same build has measured 2.4% and 8.7% an hour apart, so only an A/B taken minutes apart is a fair comparison. If in doubt, measure A again after B.
7. If CPU went up by more than 0.5 point or memory by more than 20 MB, run `scripts/perf.sh profile`, find the cause and fix it before you push.
8. For a change that keeps state (caches, timers, schedules), also check that CPU and memory don't grow over time: `scripts/perf.sh 60` (5 minutes).
9. Put the before and after numbers in the commit message.

Last baseline (October 2026): `scripts/perf-load.sh` gives about 0.3% CPU with 0 working sessions and 1% with 3, 6 or 9, at about 130 MB. With real sessions, `scripts/perf.sh` gives about 1.3% CPU and 130 MB.

## What made it slow before

Every pet redraw is a layout and render pass of the whole window. Most regressions came from adding passes or making them heavier.

- Publishing `sessions` every second when nothing changed. `refresh()` assigns only when the list changed.
- `TimelineView(.animation)`, which wakes on every display refresh. Use `.periodic` timers.
- Pets on their own clocks. Each pet changed frame at its own moment, so each one cost a layout pass, and the passes added up: 1% to 11% CPU with 3 to 9 working sessions, depending on when each started. All pets now share one clock (`PetView.clock`): about 1% with any number.
- Animating pets that don't change. A done pet is drawn once. Blinking done pets cost 2 to 4 points of CPU and grew with uptime, so the blink was removed.
- Cards with `maxHeight: .infinity` in the grid. CPU went from 3–4% to about 1.2% when that was replaced with `lineLimit(_, reservesSpace: true)`.
- Reading big files every second. Transcripts reach 50 MB, so `transcriptTitle(_:after:)` reads only what was appended. Before that, a session without a title made the deck read 1.5 MB every second (16% CPU).
- Reading process arguments every second. `backgroundShells(of:known:)` caches them per pid.

## Language

The UI is in English only. Write UI text as SwiftUI string literals (`Text("…")`, `Button("…")`) or `String(localized:)`, so translations can be added later with a `Localizable.xcstrings` file.

## Release

Push a tag like `v0.2.0`. `.github/workflows/build.yml` runs the tests, builds `ClaudeDeck.app` with that version (`./build.sh` reads `$VERSION`), zips it and publishes a GitHub release with `ClaudeDeck.zip`. Pushes to `main` and pull requests run the same build without a release. The build is signed ad hoc, not notarized: there is no Apple Developer account yet, so INSTALL.md tells users to remove the quarantine flag.

When the install steps change, update INSTALL.md: other people's agents follow it to install the app.
