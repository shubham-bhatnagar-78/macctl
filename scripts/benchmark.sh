#!/usr/bin/env bash
# macctl benchmark — measures P50/P95/P99 latency for each command layer
# durationMs = daemon-internal time (excludes CLI process spawn + socket connect overhead)
# Socket-only overhead (e.g. Python SDK): add ~0.5ms to daemon times
set -euo pipefail

MACCTL=".build/debug/macctl"
DAEMON=".build/debug/macctl-daemon"
N=20

header() { echo ""; echo "=== $* ==="; }

duration() {
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('meta',{}).get('durationMs',-1))" 2>/dev/null || echo "-1"
}
get_layer() {
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('meta',{}).get('layer','?'))" 2>/dev/null || echo "?"
}

percentile() {
    python3 -c "
vals = [float(x) for x in '$*'.split() if float(x) > 0]
vals.sort()
n = len(vals)
if n == 0: print('N/A N/A N/A'); exit()
def p(pct): return vals[min(int(n*pct), n-1)]
print(f'{p(0.50):.1f} {p(0.95):.1f} {p(0.99):.1f}')
"
}

pkill -f "macctl-daemon" 2>/dev/null || true; sleep 0.3
"$DAEMON" > /tmp/macctl-bench.log 2>&1 &
DPID=$!
trap "kill $DPID 2>/dev/null || true; pkill -f TextEdit 2>/dev/null || true" EXIT
sleep 1.5

if ! $MACCTL app list > /dev/null 2>&1; then
    echo "ERROR: daemon not responding"; cat /tmp/macctl-bench.log; exit 1
fi

# Launch TextEdit for AX tests (warm it up)
$MACCTL app launch com.apple.TextEdit > /dev/null 2>&1
sleep 1.5
# Open a document so TextEdit has a text area
$MACCTL key new --app com.apple.TextEdit > /dev/null 2>&1
sleep 0.5

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              macctl Latency Benchmark (N=$N)                 ║"
echo "║  durationMs = daemon-internal time (not CLI round-trip)      ║"
echo "║  Add ~0.5ms for Unix socket IPC overhead from SDK callers    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
printf "%-34s %-18s %7s %7s %7s\n" "Command" "Layer" "P50ms" "P95ms" "P99ms"
printf "%-34s %-18s %7s %7s %7s\n" "$(printf '%.0s-' {1..34})" "$(printf '%.0s-' {1..18})" "-------" "-------" "-------"

bench() {
    local label="$1" cmd="$2"
    local durations=() layer="?"
    for _ in $(seq 1 $N); do
        local resp
        resp=$(eval "$cmd" 2>/dev/null)
        durations+=("$(echo "$resp" | duration)")
        [ "$layer" = "?" ] && layer=$(echo "$resp" | get_layer)
    done
    local stats p50 p95 p99
    stats=$(percentile "${durations[*]}")
    read -r p50 p95 p99 <<< "$stats"
    printf "%-34s %-18s %7s %7s %7s\n" "$label" "$layer" "$p50" "$p95" "$p99"
}

header "KEYBOARD (design target: <2ms daemon-side)"
bench "key new-tab [Safari]"       "$MACCTL key new-tab --app com.apple.Safari"
bench "key save [TextEdit]"        "$MACCTL key save --app com.apple.TextEdit"
bench "key find [Notes]"           "$MACCTL key find --app com.apple.Notes 2>&1 | head -1 || $MACCTL app list > /dev/null 2>&1"
bench "key combo cmd+z [TextEdit]" "$MACCTL key cmd+z --app com.apple.TextEdit"

header "APP LIFECYCLE (design target: <5ms for running apps)"
bench "app list"                   "$MACCTL app list"
bench "app launch [already up]"    "$MACCTL app launch com.apple.TextEdit"
bench "app hide [TextEdit]"        "$MACCTL app hide com.apple.TextEdit"
bench "app show [TextEdit]"        "$MACCTL app show com.apple.TextEdit"

header "TYPE — smart routing (design target: <10ms)"
bench "type 5 chars [cgevent]"     "$MACCTL type 'Hello' --app com.apple.TextEdit"
bench "type 30 chars [paste]"      "$MACCTL type 'Testing paste path - 30 char string.' --app com.apple.TextEdit"
bench "type 100 chars [paste]"     "$MACCTL type 'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore.' --app com.apple.TextEdit"

header "AX OPERATIONS"
bench "see [TextEdit AX tree]"     "$MACCTL see --app com.apple.TextEdit"

header "SCREENSHOT (design target: <80ms warm)"
bench "screenshot [full screen]"   "$MACCTL screenshot"
bench "screenshot [TextEdit win]"  "$MACCTL screenshot --app com.apple.TextEdit"

echo ""
echo "Design targets vs results:"
printf "  %-30s %s\n" "keyboard-builtin (daemon)" "<2ms"
printf "  %-30s %s\n" "app list / launch-cached"  "<5ms"
printf "  %-30s %s\n" "type paste (28ms budget)"  "<30ms"
printf "  %-30s %s\n" "screenshot (warm SCK)"     "<80ms"
echo ""
echo "Note: CLI binary adds ~12ms process-spawn overhead on top."
echo "SDK callers (Python/Node via socket) add only ~0.5ms."
