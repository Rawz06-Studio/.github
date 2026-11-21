#!/usr/bin/env bash
# Tests de actions/prepare-image-context/prepare.sh.
# Usage : tests/prepare-image-context.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/prepare-image-context/prepare.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
count=0

check() {
  local name="$1" got="$2" want="$3"
  count=$((count + 1))
  if [[ "$got" == *"$want"* ]]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name : attendu '$want' dans :"
    while IFS= read -r line; do echo "       $line"; done <<<"$got"
    failures=$((failures + 1))
  fi
}

# run <dossier projet> VAR=VAL... : lance le script et extrait le contexte dans $CTX.
run() {
  local dir="$1"; shift
  rm -rf "$WORK/tmp" "$WORK/ctx"; mkdir -p "$WORK/tmp" "$WORK/ctx"
  OUT="$(cd "$dir" && env RUNNER_TEMP="$WORK/tmp" DOCKERFILE=Dockerfile "$@" bash "$SCRIPT" 2>&1)"
  STATUS=$?
  CTX="$WORK/ctx"
  [ -f "$WORK/tmp/image-context.tar" ] && tar -xf "$WORK/tmp/image-context.tar" -C "$CTX"
}

P="$WORK/project"
mkdir -p "$P/.output/server" "$P/bin" "$P/src" "$P/docker"
echo 'FROM scratch' >"$P/Dockerfile"
echo 'FROM alpine' >"$P/docker/prod.Dockerfile"
echo 'node_modules' >"$P/.dockerignore"
echo 'export {}' >"$P/.output/server/index.mjs"
printf '#!/bin/sh\necho hi\n' >"$P/bin/server"; chmod +x "$P/bin/server"
echo 'secret source' >"$P/src/main.rs"

run "$P" FILES=$'.output\nbin/server  # le binaire\n\n'
check "succès" "$STATUS" "0"
check "Dockerfile à la racine" "$(cat "$CTX/Dockerfile")" "FROM scratch"
check "dossier caché conservé" "$(cat "$CTX/.output/server/index.mjs" 2>&1)" "export {}"
check "binaire toujours exécutable" "$( [ -x "$CTX/bin/server" ] && echo exécutable)" "exécutable"
check ".dockerignore copié" "$(cat "$CTX/.dockerignore" 2>&1)" "node_modules"
check "fichiers non listés exclus" "$( [ -e "$CTX/src" ] && echo présent || echo absent)" "absent"

mkdir -p "$P/.rawz06-ci/actions" "$P/.git"
echo x >"$P/.rawz06-ci/actions/a.yml"; echo x >"$P/.git/HEAD"
run "$P" FILES=.
check "projet entier : sources incluses" "$(cat "$CTX/src/main.rs" 2>&1)" "secret source"
check "projet entier : .rawz06-ci exclu" "$( [ -e "$CTX/.rawz06-ci" ] && echo présent || echo absent)" "absent"
check "projet entier : .git exclu" "$( [ -e "$CTX/.git" ] && echo présent || echo absent)" "absent"
rm -rf "$P/.rawz06-ci" "$P/.git"

run "$P" FILES=bin DOCKERFILE=docker/prod.Dockerfile
check "Dockerfile personnalisé copié en ./Dockerfile" "$(cat "$CTX/Dockerfile")" "FROM alpine"

run "$P" FILES=absent
check "fichier manquant : erreur" "$OUT" "introuvable : absent"

run "$P" FILES=../etc
check "chemin hors projet : erreur" "$OUT" "hors du projet"

run "$P" FILES=$'# rien\n'
check "liste vide : erreur" "$OUT" "aucun fichier"

run "$P" FILES=bin DOCKERFILE=nope
check "Dockerfile manquant : erreur" "$OUT" "Dockerfile introuvable"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
