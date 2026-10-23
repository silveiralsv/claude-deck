# Installing Claude Deck

This guide installs and sets up Claude Deck on a Mac. It is written so that a person or an AI coding agent can follow it step by step: every step has a command and a check.

> **If you are an AI agent installing this for a user:**
> - Follow the steps in order and run each check. If a check fails, go to [Troubleshooting](#troubleshooting) instead of moving on.
> - Ask the user before step 4, because it edits their Claude Code settings. Show them the preview from step 4.
> - Tell the user before you run `xattr` in step 2a, and why.
> - Some steps need the user: installing the Command Line Tools (2b), starting Claude Code for the first time (1), and the macOS permission prompt (5). Ask them to do these; don't run them yourself.

## What the install changes

- Puts `ClaudeDeck.app` in `/Applications`.
- Creates `~/.claude-deck/` with `hook.sh`. The hook creates `~/.claude-deck/state/` on its first event.
- Adds 6 hook entries that run `~/.claude-deck/hook.sh` to the `settings.json` of each Claude Code config dir (see step 4). It backs up each file first.

Nothing else. The app makes no network requests and uses no Claude tokens: it only reads files that Claude Code writes on the Mac.

## 1. Check the requirements

```sh
sw_vers -productVersion
uname -m
ls -d ~/.claude*/sessions
ls -d /Applications/ClaudeDeck.app
pgrep -lf ClaudeDeck
```

Expected:

- macOS `15.0` or later.
- `arm64` (Apple Silicon) for the release build. On an Intel Mac, build from source (step 2b). That should work but has not been tested.
- At least one folder, for example `/Users/<user>/.claude/sessions`. Claude Deck finds the Claude Code config dirs named `~/.claude*` that have a `sessions` folder, which Claude Code creates when it runs. If the command prints nothing or "no matches found", ask the user to start Claude Code once, then check again. If the user keeps a config dir outside their home folder (`CLAUDE_CONFIG_DIR=/elsewhere`), Claude Deck can't see it.
- No `/Applications/ClaudeDeck.app` and no `ClaudeDeck` process. If either exists, Claude Deck is already installed: go to [Update](#update) instead. A process running from another path (a development build in a clone, for example) is not the installed app: leave it alone and tell the user.

**Open terminal** works with sessions running in Ghostty 1.3 or later, or in Terminal.app.

## 2a. Install the release build

```sh
curl -fL -o /tmp/ClaudeDeck.zip https://github.com/silveiralsv/claude-deck/releases/latest/download/ClaudeDeck.zip
ditto -x -k /tmp/ClaudeDeck.zip /Applications
xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app
```

Check: `ls /Applications/ClaudeDeck.app/Contents/MacOS/ClaudeDeck` prints the path.

If `curl` fails with a 404, there is no release yet: use 2b.

About `xattr`: the app is signed ad hoc and not notarized by Apple. A downloaded app gets a quarantine flag, and macOS then blocks the first launch with "Apple could not verify…". `xattr` removes that flag. Tell the user before you run it.

## 2b. Or build from source

Needs the Xcode Command Line Tools with Swift 6 or later. Full Xcode is not required.

```sh
xcode-select -p
swift --version
```

If `xcode-select -p` fails, ask the user to run `xcode-select --install`: it opens a dialog and downloads about 1 GB.

Then, from a folder of your choice (skip `git clone` and `cd` if you are already in a clone of this repo):

```sh
git clone https://github.com/silveiralsv/claude-deck.git
cd claude-deck
./build.sh
ditto ClaudeDeck.app /Applications/ClaudeDeck.app
```

Check: `./build.sh` ends with `Built ClaudeDeck.app (<version>)`, and `ls /Applications/ClaudeDeck.app` works. The version is the latest git tag, or `0.0.0` when the clone has no tags.

To run the tests too: `scripts/test.sh`. Use that script, not a bare `swift test`: with only the Command Line Tools, `swift test` can't find the `Testing` module.

## 3. Open the app

```sh
open /Applications/ClaudeDeck.app
```

Check: `pgrep -lf /Applications/ClaudeDeck.app` prints a process. A small Clawd appears in the menu bar. Clicking it shows one card per running Claude Code session.

## 4. Install the hooks

The hooks tell Claude Deck when a session is working, done or waiting for the user. Without them, the deck only knows busy or idle.

First, show the user which settings files will change:

```sh
for d in ~/.claude*/; do [ -d "${d}sessions" ] && echo "${d}settings.json -> $(realpath "${d}settings.json" 2>/dev/null || echo 'new file')"; done
```

Each line is a config dir and the real file behind its `settings.json`. Dirs whose `settings.json` is a symlink to the same file share one change. Tell the user:

- Each of those files gets 6 hook entries that run `~/.claude-deck/hook.sh`, and a backup `settings.json.claude-deck.bak` first.
- The JSON is rewritten with sorted keys and Apple's formatting (`"key" : value`). The content stays the same apart from the hooks, but if they keep `settings.json` in git, the diff will be noisy.
- The hook prints nothing, so it adds nothing to their conversations and costs no tokens. It takes about 12 ms per event.

Ask whether to go on. Then:

```sh
/Applications/ClaudeDeck.app/Contents/MacOS/ClaudeDeck --install-hooks
```

It prints the settings files it changed (with symlinks resolved, so `/private/tmp` can show as `/tmp`), or `Hooks already installed.` It also copies `hook.sh` from the app to `~/.claude-deck/hook.sh`.

Check: for each path it printed,

```sh
grep -c "claude-deck/hook.sh" <printed path>
```

Expected: `6`. After the user sends any prompt in a Claude Code session, `ls ~/.claude-deck/state` shows a `<session id>.json` file. That folder doesn't exist before the first hook event.

Running sessions usually pick up the new hooks. If a card keeps the wrong status, the user can restart that session.

## 5. Allow terminal control (the user clicks)

The first time the user clicks **Open terminal** on a card, macOS asks: "Claude Deck wants access to control Ghostty" (or Terminal). They must click **Allow**.

If they clicked **Don't Allow**: System Settings › Privacy & Security › Automation › Claude Deck, then turn on Ghostty or Terminal.

A new build has a new ad hoc signature, so macOS asks again after each update.

## 6. Optional settings

- **Keep the deck on screen:** click the menu bar Clawd, then **Show deck**. The deck opens as a window above other apps, and the app remembers it.
- **Launch at login:** System Settings › General › Login Items & Extensions › Open at Login › **+** › `ClaudeDeck.app`.

## Verify

1. `ls ~/.claude*/sessions/*.json | wc -l` counts the session files. The deck shows about that many cards: it skips sessions whose process has ended and sessions that are not interactive.
2. In any session, send a prompt. Its card turns to **working**, then **done** when Claude finishes.
3. Ask Claude to do something that needs a permission (in a session without bypass mode). The card turns to **needs you**, moves to the top, and the menu bar Clawd raises its arms.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "Apple could not verify ClaudeDeck…" on first launch | Run `xattr -dr com.apple.quarantine /Applications/ClaudeDeck.app`, or System Settings › Privacy & Security › **Open Anyway**. |
| No cards, but Claude Code is running | Check step 1: the config dir must be `~/.claude*` with a `sessions` folder. Update Claude Code if `sessions` is missing. |
| Cards never show **needs you**, or stay **working** | The hooks are missing. Run step 4, send a prompt, and check `~/.claude-deck/state`. Restart the session. |
| **Open terminal** shows "Tab not found" | The session runs in a terminal other than Ghostty 1.3+ or Terminal.app, or the Automation permission is off (step 5). |
| **Open terminal** shows "No terminal" | The session has no terminal, for example it runs inside an IDE. |
| `swift test` says "no such module 'Testing'" | Use `scripts/test.sh`. |

## Update

1. Quit the installed copy only: `pkill -f /Applications/ClaudeDeck.app/`
2. Repeat step 2a or 2b. The `ditto` there replaces the app.
3. `open /Applications/ClaudeDeck.app`
4. Run `--install-hooks` from step 4 again. It updates `~/.claude-deck/hook.sh`, and changes no settings file when the hooks are already there.

## Uninstall

1. `pkill -f /Applications/ClaudeDeck.app/`
2. In the `hooks` key of each settings file from step 4, remove every entry whose `command` is `<home>/.claude-deck/hook.sh`. Don't restore `settings.json.claude-deck.bak` blindly: it is the file from before the install and misses any later change.
3. `rm -rf ~/.claude-deck /Applications/ClaudeDeck.app`
