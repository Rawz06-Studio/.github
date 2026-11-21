#!/usr/bin/env bash
# Tests de actions/resolve-mode/resolve-mode.sh.
# Usage : tests/resolve-mode.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/resolve-mode/resolve-mode.sh"

failures=0
count=0

run() { OUT="$(env -u GITHUB_OUTPUT DEFAULT_BRANCH=main "$@" bash "$SCRIPT" 2>&1)"; STATUS=$?; }

expect() {
  local name="$1" want="$2" got
  count=$((count + 1))
  got="$(sed -n 's/^mode=//p;s/^bump=/ bump=/p;s/^pr-number=/ pr=/p' <<<"$OUT" | tr -d '\n')"
  if [ "$STATUS" -eq 0 ] && [ "$got" = "$want" ]; then
    echo "ok   - $name ($want)"
  else
    echo "FAIL - $name : attendu '$want', obtenu '$got' (code $STATUS)"
    echo "       $OUT"
    failures=$((failures + 1))
  fi
}

expect_error() {
  local name="$1" want="$2"
  count=$((count + 1))
  if [ "$STATUS" -ne 0 ] && [[ "$OUT" == *"$want"* ]]; then
    echo "ok   - $name (erreur)"
  else
    echo "FAIL - $name : erreur « $want » attendue, obtenu : $OUT"
    failures=$((failures + 1))
  fi
}

run EVENT_NAME=push REF=refs/heads/main
expect "push sur main" "release bump=auto pr="

run EVENT_NAME=push REF=refs/heads/feature/x
expect "push sur une branche" "ci bump=auto pr="

run EVENT_NAME=push REF=refs/heads/master DEFAULT_BRANCH=master
expect "branche par défaut master" "release bump=auto pr="

run EVENT_NAME=pull_request REF=refs/pull/12/merge PR_NUMBER=12 PREVIEW_LABEL=false
expect "PR sans label" "ci bump=auto pr=12"

run EVENT_NAME=pull_request REF=refs/pull/12/merge PR_NUMBER=12 PREVIEW_LABEL=true
expect "PR avec label preview" "preview bump=auto pr=12"

run EVENT_NAME=workflow_dispatch REF=refs/heads/main DISPATCH_BUMP=minor
expect "dispatch sans mode = release, bump choisi" "release bump=minor pr="

run EVENT_NAME=workflow_dispatch REF=refs/heads/feature/x DISPATCH_MODE=preview
expect "dispatch preview depuis une branche" "preview bump=auto pr="

run EVENT_NAME=workflow_dispatch REF=refs/heads/feature/x DISPATCH_MODE=release
expect_error "release refusée hors branche par défaut" "une release se fait depuis main"

run EVENT_NAME=workflow_dispatch REF=refs/heads/main DISPATCH_BUMP=auto
expect "dispatch bump auto" "release bump=auto pr="

run EVENT_NAME=schedule REF=refs/heads/main
expect "autre événement" "ci bump=auto pr="

run REQUESTED_MODE=ci EVENT_NAME=push REF=refs/heads/main
expect "mode forcé par l'appelant" "ci bump=auto pr="

run REQUESTED_BUMP=major EVENT_NAME=workflow_dispatch REF=refs/heads/main DISPATCH_BUMP=patch
expect "bump forcé par l'appelant prioritaire" "release bump=major pr="

run REQUESTED_MODE=prod EVENT_NAME=push REF=refs/heads/main
expect_error "mode invalide" "mode invalide"

run EVENT_NAME=workflow_dispatch REF=refs/heads/main DISPATCH_BUMP=huge
expect_error "bump invalide" "bump invalide"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
