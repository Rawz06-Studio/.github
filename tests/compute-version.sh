#!/usr/bin/env bash
# Tests de actions/compute-version/compute-version.sh sur des dépôts git jetables.
# Usage : tests/compute-version.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/compute-version/compute-version.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
count=0

# Crée un dépôt vide et s'y place.
new_repo() {
  local dir="$WORK/repo-$RANDOM$RANDOM"
  mkdir -p "$dir"
  cd "$dir"
  git init --quiet --initial-branch=main
  git config user.name test
  git config user.email test@example.com
  git config commit.gpgsign false
  git config tag.gpgsign false
}

commit() { git commit --quiet --allow-empty -m "$1"; }

# run VAR=VAL ... : exécute le script et mémorise ses sorties.
run() {
  OUT="$(env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY GITHUB_RUN_NUMBER=42 "$@" bash "$SCRIPT" 2>&1)" || {
    OUT="EXIT:$? $OUT"
  }
}

get() { sed -n "s/^$1=//p" <<<"$OUT"; }

expect() {
  local name="$1" key="$2" want="$3" got
  count=$((count + 1))
  got="$(get "$key")"
  if [ "$got" = "$want" ]; then
    echo "ok   - $name ($key=$want)"
  else
    echo "FAIL - $name : $key attendu '$want', obtenu '$got'"
    while IFS= read -r line; do echo "       $line"; done <<<"$OUT"
    failures=$((failures + 1))
  fi
}

expect_error() {
  local name="$1"
  count=$((count + 1))
  if [[ "$OUT" == EXIT:* ]]; then
    echo "ok   - $name (erreur attendue)"
  else
    echo "FAIL - $name : une erreur était attendue"
    failures=$((failures + 1))
  fi
}

# --- Sans tag -----------------------------------------------------------------

new_repo; commit "init"
run
expect "aucun tag, aucun fichier projet" version 0.1.0
expect "aucun tag, aucun fichier projet" bump initial
expect "aucun tag, aucun fichier projet" previous-tag ""

new_repo; commit "init"
run INITIAL_VERSION=2.0.0
expect "initial-version explicite" version 2.0.0

new_repo; commit "init"
run INITIAL_VERSION=2.0
expect_error "initial-version invalide"

new_repo
cat >pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>p</artifactId><version>3.5.0</version></parent>
  <artifactId>app</artifactId>
  <version>1.0.13-SNAPSHOT</version>
</project>
EOF
git add pom.xml; commit "init"
run
expect "pom en SNAPSHOT" version 1.0.13

new_repo
cat >pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <artifactId>app</artifactId>
  <version>${revision}</version>
  <properties><revision>0.0.0-SNAPSHOT</revision></properties>
</project>
EOF
git add pom.xml; commit "init"
run
expect "pom \${revision} placeholder" version 0.1.0

new_repo
echo '{"name":"app","version":"1.4.2"}' >package.json
git add package.json; commit "feat: init"
run
expect "package.json déjà publié" version 1.4.3

new_repo
mkdir front
echo '{"name":"app","version":"3.1.0"}' >front/package.json
git add front; commit "init"
run PROJECT_DIR=front BUMP=minor
expect "working-directory + bump forcé" version 3.2.0

new_repo
printf '[workspace]\nmembers = []\n[workspace.package]\nversion = "0.4.0"\n' >Cargo.toml
git add Cargo.toml; commit "init"
run
expect "Cargo.toml workspace" version 0.4.1

# --- Avec tags ----------------------------------------------------------------

new_repo; commit "init"; git tag v1.4.2
commit "fix: bug"; commit "chore: deps"
run
expect "fix -> patch" version 1.4.3
expect "fix -> patch" bump patch
expect "fix -> patch" previous-tag v1.4.2
expect "fix -> patch" tag v1.4.3

commit "feat(api): endpoint"
run
expect "feat -> minor" version 1.5.0

commit "refactor!: nouvelle API"
run
expect "! -> major" version 2.0.0

new_repo; commit "init"; git tag v1.0.0
git commit --quiet --allow-empty -m "fix: truc" -m "BREAKING CHANGE: le format change"
run
expect "BREAKING CHANGE dans le corps" version 2.0.0

new_repo; commit "init"; git tag v1.0.0; commit "feat: x"
run BUMP=patch
expect "bump forcé prioritaire" version 1.0.1

new_repo; commit "init"; git tag v1.2.0; git tag v1.10.0; git tag v1.9.0-rc.1; git tag latest
commit "fix: x"
run
expect "tri SemVer, rc et tags exotiques ignorés" previous-tag v1.10.0
expect "tri SemVer, rc et tags exotiques ignorés" version 1.10.1

new_repo; commit "init"; git tag v1.2.0
run
expect "HEAD déjà tagué" version 1.2.0
expect "HEAD déjà tagué" exists true
expect "HEAD déjà tagué" bump none

new_repo; commit "init"; git tag v1.0.0
git switch --quiet -c feature; commit "feat: x"
git switch --quiet main; commit "fix: y"; git tag v1.0.1
git switch --quiet feature
run MODE=preview
expect "tag non mergé ignoré + preview" version 1.1.0-rc.42
expect "tag non mergé ignoré + preview" previous-tag v1.0.0

run MODE=ci
sha="$(git rev-parse --short=7 HEAD)"
expect "mode ci" version "1.1.0-ci.$sha"
expect "mode ci" release-version 1.1.0

new_repo; commit "init"; git tag release-3.0.0; git tag v2.0.0; commit "fix: x"
run TAG_PREFIX=release-
expect "préfixe de tag personnalisé" version 3.0.1
expect "préfixe de tag personnalisé" tag release-3.0.1

run MODE=prod
expect_error "mode invalide"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
