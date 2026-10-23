#!/bin/sh
# Claude Deck hook. Keeps the latest hook event of each Claude Code session in
# ~/.claude-deck/state/<session_id>.json, where the deck app reads the status.
# It must never block Claude Code, so it always exits 0.
dir="$HOME/.claude-deck/state"
input=$(cat)
field() { printf '%s' "$input" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1; }
sid=$(field session_id)
case "$sid" in "" | *[!A-Za-z0-9-]*) exit 0 ;; esac
if [ "$(field hook_event_name)" = "SessionEnd" ]; then
  rm -f "$dir/$sid.json"
  exit 0
fi
mkdir -p "$dir"
printf '%s' "$input" > "$dir/$sid.json.$$" && mv -f "$dir/$sid.json.$$" "$dir/$sid.json"
exit 0
