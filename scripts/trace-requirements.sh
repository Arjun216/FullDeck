#!/usr/bin/env bash
# Report which FR-/NFR- IDs from docs/requirements.md have no test naming them.
# Convention (CLAUDE.md): a test's display name starts with the ID it verifies,
#   @Test("FR-8 failing grade resets the interval").
# Report only, never fails CI: many IDs are legitimately untestable until their phase lands.
set -euo pipefail
cd "$(dirname "$0")/.."

ids() { grep -rohE '(FR|NFR)-[0-9]+' "$@" 2>/dev/null | sort -u; }

REQ=$(ids docs/requirements.md)
# Test sources anywhere named *Tests* (SPM Tests/ dirs + app test targets). None yet = empty.
TEST_FILES=$(find . -path ./.git -prune -o -name '*.swift' -path '*Tests*' -print 2>/dev/null)
TESTS=$([ -n "$TEST_FILES" ] && ids $TEST_FILES || true)

covered=0 total=0 missing=""
while read -r id; do
  [ -z "$id" ] && continue
  total=$((total+1))
  if grep -qxF "$id" <<<"$TESTS"; then covered=$((covered+1)); else missing+="$id "; fi
done <<<"$REQ"

echo "Requirements traceability: $covered/$total IDs have a naming test."
[ -n "$missing" ] && echo "Untested: $missing" || echo "All requirement IDs are named by a test."
exit 0
