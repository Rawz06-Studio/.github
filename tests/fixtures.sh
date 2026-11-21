#!/usr/bin/env bash
# Vérifie, sur les mini-projets de tests/fixtures, que la version injectée par
# set-version se retrouve bien dans ce que produit le build.
#
#   tests/fixtures.sh                    # toutes les stacks (outils installés en local)
#   tests/fixtures.sh rust               # une seule
#   RUST_TARGET=x86_64-unknown-linux-musl tests/fixtures.sh rust   # + binaire statique
#
# Chaque fixture est copiée dans un dossier temporaire : le repo n'est jamais modifié.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.2.3-ci.7}"
MVN="${MVN:-mvn}"
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

# Copie la fixture et y injecte la version.
prepare() {
  DIR="$WORK/$1"
  cp -R "$ROOT/tests/fixtures/$1" "$DIR"
  python3 "$ROOT/actions/set-version/set-version.py" "$DIR" "$VERSION" >/dev/null
}

test_maven() {
  prepare maven
  local out
  out="$(cd "$DIR" && "$MVN" -q -B package 2>&1 && java -jar "target/fixture-$VERSION.jar" 2>&1)"
  check "maven : jar versionné et Implementation-Version" "$out" "fixture $VERSION"
}

test_node() {
  prepare node
  local out
  out="$(cd "$DIR" && pnpm install --frozen-lockfile --silent 2>&1 && pnpm run --silent build 2>&1)"
  check "node : version vue par le build" "$out" "fixture $VERSION"
  check "node : version embarquée dans dist/" "$(cat "$DIR/dist/version.txt" 2>&1)" "$VERSION"
}

test_php() {
  prepare php
  local out
  out="$(cd "$DIR" && composer install --no-interaction --no-progress -q --ignore-platform-req=php 2>&1 && php public/index.php 2>&1)"
  check "php : fichier VERSION lu par l'application" "$out" "fixture $VERSION"
}

test_rust() {
  prepare rust
  local out
  out="$(cd "$DIR" && cargo run --locked --quiet 2>&1)"
  check "rust : Cargo.lock cohérent et CARGO_PKG_VERSION" "$out" "fixture $VERSION"
  if [ -n "${RUST_TARGET:-}" ]; then
    out="$(cd "$DIR" && cargo build --release --locked --quiet --target "$RUST_TARGET" 2>&1 \
      && file "target/$RUST_TARGET/release/fixture")"
    check "rust : binaire statique ($RUST_TARGET)" "$out" "statically linked"
  fi
}

stacks=("$@")
[ "${#stacks[@]}" -gt 0 ] || stacks=(maven node php rust)
for stack in "${stacks[@]}"; do
  if declare -F "test_$stack" >/dev/null; then
    "test_$stack"
  else
    echo "FAIL - stack inconnue : $stack"
    count=$((count + 1))
    failures=$((failures + 1))
  fi
done

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
