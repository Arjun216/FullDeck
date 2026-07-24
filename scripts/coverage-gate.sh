#!/usr/bin/env bash
# Fail (exit 1) if a package's SOURCE line coverage is below a floor.
# CLAUDE.md testing standards: Domain >= 90%, Data >= 80%.
#
# Usage: scripts/coverage-gate.sh <package-path> <min-percent> <test-bundle-name>
#   scripts/coverage-gate.sh Packages/Domain 90 DomainPackageTests
#   scripts/coverage-gate.sh Packages/Data   80 DataPackageTests
#
# Precondition: `swift test --package-path <pkg> --enable-code-coverage` has run.
# macOS-only paths (CI runs on a macOS runner): the .xctest bundle nests the
# binary under Contents/MacOS. The `.build/debug` symlink keeps the path stable
# across toolchains/arches so the gate doesn't drift.
set -euo pipefail

pkg="${1:?package path required}"
min="${2:?min percent required}"
bundle="${3:?test bundle name required}"

prof="$pkg/.build/debug/codecov/default.profdata"
bin="$pkg/.build/debug/$bundle.xctest/Contents/MacOS/$bundle"

if [[ ! -f "$prof" || ! -x "$bin" ]]; then
  echo "coverage-gate: missing profdata or test binary under $pkg/.build/debug" >&2
  echo "  run: swift test --package-path $pkg --enable-code-coverage" >&2
  exit 2
fi

# Source-only coverage: exclude the test sources and SPM-generated .build files,
# otherwise uncovered test-runner lines dilute the number.
pct=$(xcrun llvm-cov export -summary-only \
        -instr-profile "$prof" "$bin" \
        -ignore-filename-regex='Tests|\.build' \
      | jq '.data[0].totals.lines.percent')

awk -v p="$pct" -v m="$min" -v pkg="$pkg" 'BEGIN {
  printf "%s source line coverage: %.2f%% (floor %d%%)\n", pkg, p, m
  if (p + 0 < m + 0) { print "  x below floor"; exit 1 }
  print "  ok meets floor"
}'
