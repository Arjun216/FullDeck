#!/usr/bin/env bash
# NFR-2 / NFR-3 measurement. Deliberately NOT part of CI — a shared runner is too
# noisy for a 100 ms assertion, so these numbers are taken locally and recorded in
# docs/test-plan.md §4 rather than gated. `.github/workflows/ci.yml` skips
# PerformanceUITests for the same reason.
#
#   scripts/measure-performance.sh                  # default simulator
#   scripts/measure-performance.sh "iPhone 16e"     # a specific one
#
# A simulator on an Apple-silicon Mac is FASTER than the baseline device
# (iPhone SE 3 / iPhone 12 class). A failure here is conclusive; a pass is
# evidence, not the acceptance measurement. That one needs the phone, and is on
# the manual QA checklist.
set -euo pipefail

DEVICE="${1:-iPhone 17}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${TMPDIR:-/tmp}/fulldeck-performance.xcresult"

rm -rf "$RESULTS"

echo "Measuring on: $DEVICE"
xcodebuild test \
  -project "$ROOT/FullDeck/FullDeck.xcodeproj" \
  -scheme FullDeck \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:FullDeckUITests/PerformanceUITests \
  -only-testing:FullDeckTests/GradeLatencyTests \
  -resultBundlePath "$RESULTS" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "Test case|passed|failed" || true

# xcodebuild stopped printing the "measured [...] average:" lines, so read the
# numbers out of the bundle rather than out of the log.
echo
python3 - "$RESULTS" <<'PY'
import json, subprocess, sys

bundle = sys.argv[1]


def get(*args):
    out = subprocess.run(
        ["xcrun", "xcresulttool", "get", "--legacy", "--format", "json", "--path", bundle, *args],
        capture_output=True, text=True,
    )
    return json.loads(out.stdout) if out.stdout else {}


root = get()
tests = get("--id", root["actions"]["_values"][0]["actionResult"]["testsRef"]["id"]["_value"])

cases = []


def walk(node):
    if isinstance(node, dict):
        if node.get("_type", {}).get("_name") == "ActionTestMetadata":
            ref = node.get("summaryRef", {}).get("id", {}).get("_value")
            if ref:
                cases.append((node.get("name", {}).get("_value"), ref))
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)


walk(tests)

for name, ref in cases:
    for metric in get("--id", ref).get("performanceMetrics", {}).get("_values", []):
        runs = [float(v["_value"]) for v in metric["measurements"]["_values"]]
        unit = metric.get("unitOfMeasurement", {}).get("_value", "s")
        scale, suffix = (1000, "ms") if unit.startswith("s") else (1, unit)
        avg = sum(runs) / len(runs) * scale
        print(
            f"{name}\n  n={len(runs)}  avg={avg:.2f} {suffix}  "
            f"min={min(runs) * scale:.2f} {suffix}  max={max(runs) * scale:.2f} {suffix}"
        )
PY

echo
echo "Full result bundle: $RESULTS"
echo "Targets: NFR-2 cold launch <= 2.0 s, NFR-3 grade-and-advance <= 100 ms."
echo "Record what you got in docs/test-plan.md section 4."
