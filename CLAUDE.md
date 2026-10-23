# Claude Deck

A macOS menu bar app (SwiftUI, Swift Package, no Xcode project) that shows the running Claude Code sessions as cards, with a pixel Clawd per session. README.md explains where each piece of data comes from.

## Commands

- Build: `./build.sh` (writes `ClaudeDeck.app`)
- Relaunch after a build: `pkill -x ClaudeDeck; open ClaudeDeck.app`
- Tests: `scripts/test.sh`
- Performance: `scripts/perf.sh [samples]` and `scripts/perf.sh profile`

## Measure performance before every commit and push

The deck runs all day, so a change that costs CPU or memory is a regression even when it works. Before you commit or push a change to app code:

1. Keep the deck window open (Show deck) for every measurement. A closed window doesn't draw and shows nothing.
2. With the build from before your change running, run `scripts/perf.sh`. This is the baseline.
3. Build and relaunch your change, wait about 10 seconds, and run `scripts/perf.sh` again.
4. Compare the runs only when their `sessions` lines match. Busy sessions animate their pet, so more busy sessions means more CPU.
5. Measure back to back. The same build has measured 2.4% and 8.7% an hour apart, so only an A/B taken minutes apart is a fair comparison. If in doubt, measure A again after B.
6. If CPU went up by more than 0.5 point or memory by more than 20 MB, run `scripts/perf.sh profile`, find the cause and fix it before you push.
7. For a change that keeps state (caches, timers, schedules), also check that CPU and memory don't grow over time: `scripts/perf.sh 60` (5 minutes).
8. Put the before and after numbers in the commit message.

Last baseline (October 2026, deck window open, 2 busy and 8 idle sessions): about 1.7% CPU and 130 MB.

## What made it slow before

Every pet redraw is a layout and render pass of the whole window. Most regressions came from adding passes or making them heavier.

- Publishing `sessions` every second when nothing changed. `refresh()` assigns only when the list changed.
- `TimelineView(.animation)`, which wakes on every display refresh. Use `.periodic` timers.
- Animating pets that don't change. A done pet is drawn once. Blinking done pets cost 2 to 4 points of CPU and grew with uptime, so the blink was removed.
- Cards with `maxHeight: .infinity` in the grid. CPU went from 3–4% to about 1.2% when that was replaced with `lineLimit(_, reservesSpace: true)`.
- Reading big files every second. Transcripts reach 50 MB, so `transcriptTitle(_:after:)` reads only what was appended. Before that, a session without a title made the deck read 1.5 MB every second (16% CPU).
- Reading process arguments every second. `backgroundShells(of:known:)` caches them per pid.

## Language

The UI is in English only. Write UI text as SwiftUI string literals (`Text("…")`, `Button("…")`) or `String(localized:)`, so translations can be added later with a `Localizable.xcstrings` file.
