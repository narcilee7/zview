#!/bin/sh
# Phase 0 bench: measures binary size + RSS at idle + cold-start time.
# Real RSS sweep (30 days vs 1 min) is a Phase 1+ concern.

set -e

ZIG="${ZIG:-/Users/Zhuanz/zig/zig-aarch64-macos-0.15.2/zig}"
BIN=./zig-out/bin/counter
LOG=./zig-out/bench.log

cd "$(dirname "$0")/.."

echo "═══ zview Phase 0 bench ═══" | tee "$LOG"

# 1. Build both Debug and ReleaseSmall
echo "\n[1/4] zig build -Doptimize=ReleaseSmall ..." | tee -a "$LOG"
"$ZIG" build -Doptimize=ReleaseSmall 2>&1 | tee -a "$LOG"

if [ ! -x "$BIN" ]; then
  echo "ERROR: $BIN not produced" >&2
  exit 1
fi

# 2. Binary size
SIZE=$(stat -f %z "$BIN")
SIZE_KB=$((SIZE / 1024))
echo "\n[2/4] binary size: ${SIZE_KB} KB (${SIZE} bytes)" | tee -a "$LOG"

# 3. Cold start + RSS at multiple intervals
echo "\n[3/4] cold start (sample RSS over time) ..." | tee -a "$LOG"
"$BIN" >/tmp/zview-stdout.log 2>/tmp/zview-stderr.log &
PID=$!
START=$(date +%s%N)

# Sample RSS at t=0.2s, 0.6s, 1.5s
for INTERVAL in 0.2 0.4 0.9; do
  sleep "$INTERVAL"
  if ps -p "$PID" >/dev/null 2>&1; then
    ELAPSED_MS=$(awk -v s="$START" -v e="$(date +%s%N)" 'BEGIN { printf "%d", (e - s) / 1000000 }')
    RSS_KB=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || echo "?")
    printf "  t=%4dms  RSS=%s KB\n" "$ELAPSED_MS" "$RSS_KB" | tee -a "$LOG"
  else
    echo "  process exited unexpectedly at t~$(awk -v s="$START" -v e="$(date +%s%N)" 'BEGIN { printf "%d", (e - s) / 1000000 }')ms" | tee -a "$LOG"
    cat /tmp/zview-stderr.log | tee -a "$LOG"
    break
  fi
done

# 4. Kill + cleanup
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
END=$(date +%s%N)
ELAPSED_MS=$(awk -v s="$START" -v e="$END" 'BEGIN { printf "%d", (e - s) / 1000000 }')
echo "  total wall time: ${ELAPSED_MS} ms (includes sampling overhead)" | tee -a "$LOG"

# 5. Source footprint
echo "\n[4/4] source footprint:" | tee -a "$LOG"
find src examples -type f \( -name "*.zig" -o -name "*.m" -o -name "*.c" -o -name "*.html" -o -name "*.js" -o -name "*.css" \) | xargs wc -l 2>/dev/null | tee -a "$LOG"

echo "\n═══ bench complete: see $LOG ═══" | tee -a "$LOG"
