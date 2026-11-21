#!/usr/bin/env bash
# Tests de actions/set-version/set-version.py sur des projets jetables.
# Usage : tests/set-version.sh
# shellcheck disable=SC2016 # les ${revision} attendus sont littéraux
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/set-version/set-version.py"
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

project() { DIR="$WORK/$1"; mkdir -p "$DIR"; }
run() { OUT="$(GITHUB_OUTPUT="$WORK/output" python3 "$SCRIPT" "$@" 2>&1)"; STATUS=$?; }

# --- Maven ----------------------------------------------------------------------
project maven
cat >"$DIR/pom.xml" <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <artifactId>app</artifactId>
  <version>${revision}</version>
  <properties><revision>0.0.0-SNAPSHOT</revision></properties>
</project>
EOF
run "$DIR" 1.4.3
check "maven : succès" "$STATUS" "0"
check "maven : maven.config créé" "$(cat "$DIR/.mvn/maven.config")" "-Drevision=1.4.3"
check "maven : pom intact" "$(cat "$DIR/pom.xml")" '<version>${revision}</version>'
check "maven : sortie stacks" "$(cat "$WORK/output")" "stacks=maven"

printf -- '-T 1C\n-Drevision=9.9.9\n' >"$DIR/.mvn/maven.config"
run "$DIR" v1.5.0-rc.3
check "maven : préfixe v retiré, ancienne révision remplacée" "$(cat "$DIR/.mvn/maven.config")" $'-T 1C\n-Drevision=1.5.0-rc.3'
check "maven : une seule révision" "$(grep -c revision "$DIR/.mvn/maven.config")" "1"

project maven-literal
printf '<project xmlns="http://maven.apache.org/POM/4.0.0"><version>1.0.13-SNAPSHOT</version></project>\n' >"$DIR/pom.xml"
run "$DIR" 1.0.13
check "maven : version littérale refusée" "$STATUS" "1"
check "maven : message explicite" "$OUT" '${revision}'

# --- Node -----------------------------------------------------------------------
project node
printf '{\n    "name": "app",\n    "version": "0.0.0",\n    "private": true\n}\n' >"$DIR/package.json"
run "$DIR" 2.1.0
check "node : version écrite" "$(cat "$DIR/package.json")" '"version": "2.1.0"'
check "node : indentation conservée" "$(cat "$DIR/package.json")" '    "private": true'

project node-noversion
printf '{"name":"app"}\n' >"$DIR/package.json"
run "$DIR" 2.1.0
check "node : champ version ajouté" "$(cat "$DIR/package.json")" '"version": "2.1.0"'

# --- Rust -----------------------------------------------------------------------
project rust
cat >"$DIR/Cargo.toml" <<'EOF'
[package]
name = "unbing"
authors = ["moi"]
version = "0.0.0"
edition = "2024"

[dependencies]
serde = { version = "1.0.200", features = ["derive"] }
EOF
cat >"$DIR/Cargo.lock" <<'EOF'
version = 4

[[package]]
name = "serde"
version = "1.0.200"
source = "registry+https://github.com/rust-lang/crates.io-index"

[[package]]
name = "unbing"
version = "0.0.0"
dependencies = [
 "serde",
]
EOF
run "$DIR" 3.0.1
check "rust : [package] mis à jour" "$(cat "$DIR/Cargo.toml")" $'authors = ["moi"]\nversion = "3.0.1"'
check "rust : dépendance intacte" "$(cat "$DIR/Cargo.toml")" 'version = "1.0.200"'
check "rust : lock local mis à jour" "$(cat "$DIR/Cargo.lock")" $'name = "unbing"\nversion = "3.0.1"'
check "rust : lock externe intact" "$(cat "$DIR/Cargo.lock")" $'name = "serde"\nversion = "1.0.200"'

project rust-workspace
mkdir -p "$DIR/crates/server" "$DIR/crates/client" "$DIR/crates/tool"
cat >"$DIR/Cargo.toml" <<'EOF'
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.package]
version = "0.0.0"
edition = "2024"
EOF
printf '[package]\nname = "tracker-server"\nversion.workspace = true\n' >"$DIR/crates/server/Cargo.toml"
printf '[package]\nname = "tracker-client"\nversion = { workspace = true }\n' >"$DIR/crates/client/Cargo.toml"
printf '[package]\nname = "tool"\nversion = "0.3.0"\n' >"$DIR/crates/tool/Cargo.toml"
printf 'version = 4\n\n[[package]]\nname = "tool"\nversion = "0.3.0"\n\n[[package]]\nname = "tracker-client"\nversion = "0.0.0"\n\n[[package]]\nname = "tracker-server"\nversion = "0.0.0"\n' >"$DIR/Cargo.lock"
run "$DIR" 1.2.0
check "rust workspace : [workspace.package]" "$(cat "$DIR/Cargo.toml")" 'version = "1.2.0"'
check "rust workspace : membres hérités dans le lock" "$(cat "$DIR/Cargo.lock")" $'name = "tracker-client"\nversion = "1.2.0"'
check "rust workspace : serveur dans le lock" "$(cat "$DIR/Cargo.lock")" $'name = "tracker-server"\nversion = "1.2.0"'
check "rust workspace : membre à version propre intact" "$(cat "$DIR/Cargo.lock")" $'name = "tool"\nversion = "0.3.0"'

# --- PHP ------------------------------------------------------------------------
project php
printf '{"name":"rawz06/nightbot-admin"}\n' >"$DIR/composer.json"
run "$DIR" 1.0.0
check "php : fichier VERSION" "$(cat "$DIR/VERSION")" "1.0.0"

# --- Cas limites ----------------------------------------------------------------
project vide
run "$DIR" 1.0.0
check "aucun fichier projet : erreur" "$STATUS" "1"

project fullstack
printf '{"name":"front","version":"0.0.0"}\n' >"$DIR/package.json"
printf '{"name":"x/y"}\n' >"$DIR/composer.json"
run "$DIR" 4.0.0
check "plusieurs stacks dans un dossier" "$(tail -1 "$WORK/output")" "stacks=node php"

run "$DIR" 4.0
check "version invalide refusée" "$STATUS" "1"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
