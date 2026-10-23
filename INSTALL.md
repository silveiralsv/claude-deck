# Installing Claude Deck

This guide installs and sets up Claude Deck on a Mac. It is written so that a person or an AI coding agent can follow it step by step: every step has a command and a check.

> **If you are an AI agent installing this for a user:** follow the steps in order and run each check. Ask the user before step 4, because it edits their Claude Code settings. Steps 5 and 6 need the user to click in macOS, so tell them what to expect. Don't skip a failed check: go to [Troubleshooting](#troubleshooting).

## What the install changes

- Puts `ClaudeDeck.app` in `/Applications`.
- Creates `~/.claude-deck/` with `hook.sh` and a `state/` folder.
- Adds 6 hook entries that run `~/.claude-deck/hook.sh` to the `settings.json` of each Claude Code config dir (see step 4). It backs up each file first.

Nothing else. The app makes no network requests and uses no Claude tokens: it only reads files that Claude Code writes on the Mac.

## 1. Check the requirements

```sh
sw_vers -productVersion
uname -m
ls -d ~/.claude*/sessions
```

Expected:

- macOS `15.0` or later.
- `arm64` (Apple Silicon). The release build is arm64 only. On an Intel Mac, build from source (step 2b).
- At least one folder, for example `/Users/<user>/.claude/sessions`. Claude Deck finds Claude Code config dirs named `~/.claude*` that have a `sessions` folder, which Claude Code creates when it runs. If there is none, start Claude Code once (`claude`) and check again. If the user keeps a config dir outside their home folder (`CLAUDE_CONFIG_DIR=/elsewhere`), Claude Deck can't see it.

**Open terminal** works with sessions running in Ghostty 1.3 or later, or in Terminal.app.

## 2a. Install the release build

```sh
curl -fL -o /tmp/ClaudeDeck.zip https://github.com/silveiralsv/claude-deck/releases/latest/download/ClaudeDeck.zip
ditto -x -k /tmp/ClaudeDeck.zip /Applications
xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app
```

Check: `ls /Applications/ClaudeDeck.app/Contents/MacOS/ClaudeDeck` prints the path.

The app is signed ad hoc, not notarized by Apple. The `xattr` command removes the quarantine flag, so macOS doesn't block the first launch with "Apple could not verify…". If `curl` fails with a 404, there is no release yet: use 2b.

## 2b. Or build from source

Needs the Xcode Command Line Tools (`xcode-select --install`) with Swift 6 or later. Full Xcode is not required.

```sh
xcode-select -p
swift --version
git clone https://github.com/silveiralsv/claude-deck.git
cd claude-deck
./build.sh
ditto ClaudeDeck.app /Applications/ClaudeDeck.app
```

Check: `./build.sh` ends with `Built ClaudeDeck.app`, and `ls /Applications/ClaudeDeck.app` works.

To run the tests too: `scripts/test.sh`. Use that script, not a bare `swift test`: with only the Command Line Tools, `swift test` can't find the `Testing` module.

## 3. Open the app

```sh
open /Applications/ClaudeDeck.app
```

Check: `pgrep -x ClaudeDeck` prints a process id. A small Clawd appears in the menu bar. Clicking it shows one card per running Claude Code session.

## 4. Install the hooks

Ask the user first. This edits Claude Code's `settings.json` files.

```sh
/Applications/ClaudeDeck.app/Contents/MacOS/ClaudeDeck --install-hooks
```

It prints the settings files it changed, or `Hooks already installed.` What it does:

- Copies `hook.sh` from the app to `~/.claude-deck/hook.sh`.
- For each config dir from step 1, adds `~/.claude-deck/hook.sh` to the `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop` and `SessionEnd` hooks of its `settings.json`. A `settings.json` that is a symlink is followed, and each real file is changed once.
- Before it changes a file, it copies it to `settings.json.claude-deck.bak`.
- Rewrites the JSON with sorted keys. The content stays the same apart from the new hooks.

Check:

```sh
grep -c "claude-deck/hook.sh" ~/.claude/settings.json
```

Expected: `6` for each changed file. After the user sends any prompt in a Claude Code session, `ls ~/.claude-deck/state` shows a `<session id>.json` file.

Running sessions usually pick up the new hooks. If a card keeps the wrong status, restart that session.

The hook prints nothing, so it adds nothing to the conversation and costs no tokens. It takes about 12 ms per event.

## 5. Allow terminal control (the user clicks)

The first time the user clicks **Open terminal** on a card, macOS asks: "Claude Deck wants access to control Ghostty" (or Terminal). They must click **Allow**.

If they clicked **Don't Allow**: System Settings › Privacy & Security › Automation › Claude Deck, then turn on Ghostty or Terminal.

A new build has a new ad hoc signature, so macOS asks again after each update.

## 6. Optional settings

- **Keep the deck on screen:** click the menu bar Clawd, then **Show deck**. The deck opens as a window above other apps, and the app remembers it.
- **Launch at login:** System Settings › General › Login Items › Open at Login › **+** › `ClaudeDeck.app`.

## Verify

1. `ls ~/.claude*/sessions/*.json | wc -l` counts the running sessions. The deck shows the same number of cards.
2. In any session, send a prompt. Its card turns to **working**, then **done** when Claude finishes.
3. Ask Claude to do something that needs a permission (in a session without bypass mode). The card turns to **needs you**, moves to the top, and the menu bar Clawd raises its arms.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "Apple could not verify ClaudeDeck…" on first launch | Run `xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app`, or System Settings › Privacy & Security › **Open Anyway**. |
| No cards, but Claude Code is running | Check step 1: the config dir must be `~/.claude*` with a `sessions` folder. Update Claude Code if `sessions` is missing. |
| Cards never show **needs you**, or stay **working** | The hooks are missing. Run step 4 and check `~/.claude-deck/state`. Restart the session. |
| **Open terminal** shows "Tab not found" | The session runs in a terminal other than Ghostty 1.3+ or Terminal.app, or the Automation permission is off (step 5). |
| **Open terminal** shows "No terminal" | The session has no terminal, for example it runs inside an IDE. |
| `swift test` says "no such module 'Testing'" | Use `scripts/test.sh`. |

## Update

Repeat step 2a or 2b, then `pkill -x ClaudeDeck; open /Applications/ClaudeDeck.app`. Run step 4 again too: it updates `~/.claude-deck/hook.sh` and does nothing else when the hooks are already there.

## Uninstall

1. `pkill -x ClaudeDeck`
2. In the `hooks` key of each `settings.json` from step 4, remove every entry whose `command` is `<home>/.claude-deck/hook.sh`. Don't restore `settings.json.claude-deck.bak` blindly: it is the file from before the install and misses any later change.
3. `rm -rf ~/.claude-deck /Applications/ClaudeDeck.app`
