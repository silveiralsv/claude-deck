#!/bin/zsh
# Measures CPU and memory of Claude Deck builds with none, a third, two thirds and all of N sessions working.
# The sessions are made up, under a fake HOME, so the numbers don't depend on your real sessions.
#   [SESSIONS=N] scripts/perf-load.sh [app ...]   N defaults to 9, app to ClaudeDeck.app (run ./build.sh first)
# Your running deck can stay open. Keep the screen awake: a deck that isn't drawn shows nothing.
cd "$(dirname "$0")/.."
apps=(${@:-ClaudeDeck.app})
D=$(mktemp -d)
mkdir -p "$D/.claude/sessions" "$D/.claude/projects/-load" "$D/.claude-deck/state"
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

typeset -A PID SID
n=${SESSIONS:-9}
for i in {1..$n}; do
  sleep 3600 &
  last=$!; PID[$i]=$last
  SID[$i]=$(uuidgen | tr 'A-Z' 'a-z')
  printf '{"type":"ai-title","aiTitle":"Session %s","sessionId":"%s"}\n' $i ${SID[$i]} > "$D/.claude/projects/-load/${SID[$i]}.jsonl"
done
trap 'kill ${(v)PID} 2>/dev/null; rm -rf "$D"' EXIT

# state <session> working|done
state() {
  local hook=Stop live=idle
  [ $2 = working ] && { hook=PreToolUse; live=busy; }
  printf '{"session_id":"%s","hook_event_name":"%s","tool_name":"Bash"}' ${SID[$1]} $hook > "$D/.claude-deck/state/${SID[$1]}.json"
  printf '{"pid":%s,"sessionId":"%s","cwd":"/load/p%s","name":"p%s","kind":"interactive","status":"%s","statusUpdatedAt":%s,"startedAt":%s}' \
    ${PID[$1]} ${SID[$1]} $1 $1 $live $(now_ms) $((1792000000000 + $1)) > "$D/.claude/sessions/${PID[$1]}.tmp"
  mv "$D/.claude/sessions/${PID[$1]}.tmp" "$D/.claude/sessions/${PID[$1]}.json"
}

for app in $apps; do
  for i in {1..$n}; do state $i done; done
  HOME=$D "$app/Contents/MacOS/ClaudeDeck" >/dev/null 2>&1 &
  pid=$!
  sleep 6
  working=0
  for target in 0 $((n / 3)) $((2 * n / 3)) $n; do
    # Sessions start working at different moments, like in real use.
    while (( working < target )); do (( working++ )); state $working working; sleep 0.37; done
    sleep 4
    cpu=$(for _ in 1 2 3 4; do top -l 2 -s 5 -pid $pid -stats cpu | tail -1; done | tr '\n' ' ')
    avg=$(echo $cpu | awk '{ for (i = 1; i <= NF; i++) s += $i; printf "%.1f", s / NF }')
    mem=$(footprint $pid | grep -m1 Footprint | sed -E 's/.*Footprint: ([0-9.]+ [KMG]B).*/\1/')
    echo "$app | $target of $n working | cpu avg ${avg}% ($cpu) | $mem"
  done
  # SIGKILL: a normal quit would save "deck hidden" in the preferences your own deck shares.
  kill -9 $pid
done
