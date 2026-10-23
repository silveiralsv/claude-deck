#!/bin/sh
# Smoke test for hook.sh: feeds sample hook events and checks the state files.
set -e
hook="$(cd "$(dirname "$0")" && pwd)/hook.sh"
HOME=$(mktemp -d)
export HOME
state="$HOME/.claude-deck/state"

echo '{"session_id":"abc-123","hook_event_name":"PreToolUse","tool_name":"Bash"}' | sh "$hook"
grep -q '"PreToolUse"' "$state/abc-123.json"

echo '{"session_id":"abc-123","hook_event_name":"Stop"}' | sh "$hook"
grep -q '"Stop"' "$state/abc-123.json"

echo '{"session_id":"../escape","hook_event_name":"Stop"}' | sh "$hook"
[ ! -e "$HOME/.claude-deck/escape.json" ]

echo '{"session_id":"abc-123","hook_event_name":"SessionEnd"}' | sh "$hook"
[ ! -e "$state/abc-123.json" ]

rm -rf "$HOME"
echo "hook.sh ok"
