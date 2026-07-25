#!/usr/bin/env bash
# Fail (exit 1) if any TEST source uses wall-clock time or unseeded randomness.
# CLAUDE.md testing standards: tests inject the Clock and seed their RNG, so the
# suite is reproducible. A flaky suite stops being believed.
#
# Scope: every *.swift under a "*Tests" directory (DomainTests, DataTests,
# FullDeckTests, FullDeckUITests, ...), excluding .build. Report-and-fail: it
# prints the offending lines so the fix is obvious.
#
# Portability: bash 3.2 (macOS/CI default) — no mapfile. Assumes test paths have
# no spaces (true here: packages + the FullDeck app target are space-free).
set -uo pipefail

files=$(
  find . -path '*/.build/*' -prune -o -type f -name '*.swift' -print \
    | grep -E '/[A-Za-z0-9_]*Tests/' || true
)

if [[ -z "$files" ]]; then
  echo "determinism-check: no test sources found yet (nothing to check)"
  exit 0
fi

status=0

# Wall-clock "now", sleeps, and unseeded system RNG are never allowed in tests.
# Both spellings of Date-now are caught: Date() and Date.now. (Date(timeIntervalSince1970:)
# is fine — it's a fixed instant, not the clock.)
# shellcheck disable=SC2086
if grep -nE 'Date\(\)|Date\.now|Task\.sleep|Thread\.sleep|arc4random|SystemRandomNumberGenerator' $files; then
  status=1
fi

# `.random(` is allowed ONLY with an explicit `using:` seeded generator
# (Phase 5's seeded random-walk invariants rely on that form).
# shellcheck disable=SC2086
if grep -nE '\.random\(' $files | grep -v 'using:'; then
  status=1
fi

if [[ $status -ne 0 ]]; then
  echo ""
  echo "x determinism-check: tests must use the injected Clock and a seeded RNG."
  echo "  - replace Date() with the injected clock's today"
  echo "  - seed randomness: .random(in: ..., using: &rng)"
fi
exit $status
