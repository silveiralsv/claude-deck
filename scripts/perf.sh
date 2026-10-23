#!/bin/sh
# Measures the running Claude Deck. Run it with the deck window open.
#   scripts/perf.sh [samples]   CPU (one 5 s sample each, 8 by default), memory and session states
#   scripts/perf.sh profile     samples per function over 10 s (1 sample is about 1 ms of CPU)
set -e
pid=$(pgrep -x ClaudeDeck) || { echo "Claude Deck is not running"; exit 1; }

if [ "$1" = profile ]; then
  out=$(mktemp)
  sample "$pid" 10 -file "$out" >/dev/null 2>&1
  # A function counts once per stack it shows up in, so callers include their callees.
  grep -E "\(in ClaudeDeck\)|NSHostingView\.layout\(\)  |CA::Transaction::commit\(\)" "$out" \
    | sed -E 's/^[^0-9]*([0-9]+) (.*) \(in .*/\1 \2/' \
    | awk '{ n = $1; $1 = ""; total[$0] += n } END { for (f in total) print total[f], f }' \
    | sort -rn | head -15
  rm -f "$out"
  exit 0
fi

# Busy sessions redraw their pet, so compare runs only when these counts match.
states=$(cat ~/.claude*/sessions/*.json 2>/dev/null | grep -o '"status":"[a-z]*"' | cut -d'"' -f4 | sort | uniq -c | tr -s ' ' | tr '\n' ' ')
echo "sessions:$states"
cpu=$(for _ in $(seq "${1:-8}"); do top -l 2 -s 5 -pid "$pid" -stats cpu | tail -1; done | tr '\n' ' ')
echo "cpu %: $cpu"
echo "$cpu" | awk '{ for (i = 1; i <= NF; i++) { s += $i; if ($i > max) max = $i } printf "cpu avg: %.1f%%  max: %.1f%%\n", s / NF, max }'
footprint "$pid" | grep -m1 Footprint | sed -E 's/.*Footprint: ([0-9.]+ [KMG]B).*/memory: \1/'
