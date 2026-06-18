#!/bin/bash
# Stress test for concurrency safety of stop_handler.py.
# Forks N processes, each invokes the stop hook with the same session_id.
# Asserts the final turn counter equals N (no lost increments).
set -e

N="${1:-50}"
scriptDir="$(cd "$(dirname "$0")"/.. && pwd)"
stateDir=$(mktemp -d)
sessionId="stress-$$-$(date +%s)"

cleanup() { rm -rf "$stateDir"; }
trap cleanup EXIT

# Each worker pipes a minimal Stop payload to stop_handler.py
worker() {
    echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$1\"}" | \
        ALIBABACLOUD_TELEMETRY_STATE_DIR="$stateDir" \
        python3 "$scriptDir/lib/stop_handler.py" >/dev/null 2>&1
}

# Fork N workers
for i in $(seq 1 "$N"); do
    worker "$sessionId" &
done
wait

# Read final turn from state
final=$(ALIBABACLOUD_TELEMETRY_STATE_DIR="$stateDir" \
    python3 "$scriptDir/lib/state.py" show \
        --client claude-code --session "$sessionId" 2>/dev/null \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); print(d.get('turn',-1))")

if [ "$final" = "$N" ]; then
    echo "PASS: stress test ($N workers, final turn=$final)"
    exit 0
else
    echo "FAIL: stress test (expected $N, got $final — lost $((N-final)) increments)"
    exit 1
fi
