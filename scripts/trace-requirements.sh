#!/usr/bin/env bash
# Report which FR-/NFR- IDs from docs/requirements.md are NAMED by a test.
#
# "Named" is deliberately weaker than "covered", and the output says so. This
# script used to print "21/30 IDs have a naming test", which read as coverage
# and was not (C-4). Two things were wrong with it:
#
#   1. It matched the bare ID *anywhere* in a test file, so a doc comment
#      counted. NFR-4, NFR-5, NFR-6 and NFR-12 were all "covered" by a single
#      comment line in FullDeckUITests.swift. Deleting that comment would have
#      dropped the number without changing one test.
#   2. It could not see XCTest at all. A Swift identifier cannot contain a
#      hyphen, so the real audit test — testNFR4NFR5NFR6AccessibilityAudit... —
#      never matched, and the comment above it was the only evidence.
#
# What it still cannot do, and what the header therefore warns about: a
# requirement with several acceptance clauses is "named" by a test that covers
# only one of them. FR-16 is the case that mattered — two pipeline tests name it
# for the pack-metadata clause, while the credits screen its other clause
# requires does not exist (N-4). Hence the pipeline-only warning below, and
# hence every count here being a floor.
#
# Report only, never fails CI: many IDs are legitimately untestable until their
# phase lands. Run with --self-test to check the matcher itself.
set -euo pipefail

# A test NAMES a requirement when its display name starts with the ID — the
# CLAUDE.md convention. Three spellings, one per framework:
#   @Test("FR-8 failing grade resets the interval")     Swift Testing
#   """FR-16 every generated pack carries the credit"""  pytest docstring
#   func testNFR4NFR5NFR6AccessibilityAudit()            XCTest, no hyphens
names_in() {
  {
    # `((FR|NFR)-[0-9]+ ?)+` so a Swift Testing name can lead with more than one
    # ID, which the XCTest spelling below has always allowed. One test really can
    # be the evidence for two requirements — FR-9 "state is persisted" and
    # NFR-11 "the grade made just before termination is not the one lost" are the
    # same fact from two angles — and before this the second ID was silently
    # invisible to the report.
    grep -ohE '@Test\("((FR|NFR)-[0-9]+ ?)+' "$@" || true
    grep -ohE '"""((FR|NFR)-[0-9]+ ?)+' "$@" || true
    # Every ID in the identifier, so one audit function can name three.
    grep -ohE 'func +test(FR|NFR)[0-9]+[A-Za-z0-9_]*' "$@" || true
  } 2>/dev/null |
    grep -oE '(FR|NFR)-?[0-9]+' |
    sed -E 's/^(NFR|FR)([0-9])/\1-\2/' |
    sort -u
}

self_test() {
  local dir status=0
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' RETURN

  cat >"$dir/fixture.swift" <<'FIXTURE'
/// NFR-4, NFR-5, NFR-6: a doc comment must NOT count as naming anything.
@Test("FR-8 failing grade resets the interval")
func somethingElse() {}
@Test("FR-9 NFR-11 two IDs at the front both count")
func twoIDs() {}
func testNFR4NFR5AccessibilityAudit() {}
// FR-99 in a trailing comment must not count either.
FIXTURE
  cat >"$dir/test_fixture.py" <<'FIXTURE'
def test_credit():
    """FR-16 every generated pack carries the CC-BY-SA 4.0 credit."""
FIXTURE

  local got want
  got=$(names_in "$dir/fixture.swift" "$dir/test_fixture.py" | tr '\n' ' ')
  want="FR-16 FR-8 FR-9 NFR-11 NFR-4 NFR-5 "
  if [ "$got" != "$want" ]; then
    echo "x self-test: matcher returned [$got], expected [$want]"
    status=1
  fi
  # NFR-6 appears only in the comment, so its absence above is the point.
  case " $got " in *" NFR-6 "*) echo "x self-test: a doc comment counted as a name"; status=1 ;; esac
  [ $status -eq 0 ] && echo "ok trace-requirements self-test"
  return $status
}

cd "$(dirname "$0")/.."
[ "${1:-}" = "--self-test" ] && { self_test; exit $?; }

layer_of() {
  case $1 in
    Packages/Domain/*) echo domain ;;
    Packages/Data/*) echo data ;;
    */FullDeckUITests/*) echo ui ;;
    */FullDeckTests/*) echo app ;;
    pipeline/*) echo pipeline ;;
    *) echo other ;;
  esac
}

# -t- -k1,1 -k2,2n so FR-2 sorts before FR-10 rather than after FR-1.
REQ=$(grep -rohE '(FR|NFR)-[0-9]+' docs/requirements.md | sort -u -t- -k1,1 -k2,2n)
TEST_FILES=$(
  find . -path ./.git -prune -o -name '*.swift' -path '*Tests*' -print
  find . -path '*/.venv/*' -prune -o -name 'test_*.py' -print
)

# id -> space-separated layers that name it, built once rather than per ID.
evidence_file=$(mktemp)
trap 'rm -f "$evidence_file"' EXIT
while read -r file; do
  [ -z "$file" ] && continue
  layer=$(layer_of "${file#./}")
  for id in $(names_in "$file"); do
    echo "$id $layer"
  done
done <<<"$TEST_FILES" | sort -u >"$evidence_file"

echo "Requirements traceability — this counts NAMES, not coverage."
echo "An ID is 'named' when a test's display name starts with it. A requirement"
echo "with several acceptance clauses is named by a test covering only one, so"
echo "every number below is a FLOOR. Report only; never gates."
echo

named=0 total=0 missing="" warnings=""
while read -r id; do
  [ -z "$id" ] && continue
  total=$((total + 1))
  layers=$(awk -v id="$id" '$1 == id {print $2}' "$evidence_file" | sort -u | tr '\n' ' ')
  if [ -z "$layers" ]; then
    missing+="$id "
    continue
  fi
  named=$((named + 1))
  printf "  %-7s %s\n" "$id" "${layers% }"
  # A requirement whose text says "the app" but whose only evidence is the
  # content pipeline. This is the exact shape that hid N-4.
  if [ "${layers% }" = "pipeline" ] &&
    sed -n "/^### $id /,/^### /p" docs/requirements.md | grep -qi 'the app'; then
    warnings+="  $id names the app in its text, but only pipeline tests name $id.\n"
  fi
done <<<"$REQ"

echo
echo "Named by at least one test: $named/$total"
[ -n "$missing" ] && echo "Named by none: $missing" || echo "Every requirement ID is named by a test."
[ -n "$warnings" ] && printf "\nApp requirements with pipeline-only evidence:\n%b" "$warnings"
exit 0
