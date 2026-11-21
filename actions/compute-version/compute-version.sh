#!/usr/bin/env bash
# Calcule la prochaine version à partir des tags git et des messages de commit.
#
# Variables d'entrée :
#   MODE             release | preview | ci            (défaut : release)
#   BUMP             auto | patch | minor | major      (défaut : auto)
#   INITIAL_VERSION  version exacte de la 1re release si aucun tag n'existe
#   TAG_PREFIX       préfixe des tags                  (défaut : v)
#   PROJECT_DIR      dossier du fichier projet          (défaut : .)
#   GITHUB_RUN_NUMBER, GITHUB_OUTPUT                   fournis par GitHub Actions
#
# Sorties (dans $GITHUB_OUTPUT, sinon sur stdout) :
#   version, release-version, tag, previous-tag, bump, exists
set -euo pipefail

MODE="${MODE:-release}"
BUMP="${BUMP:-auto}"
INITIAL_VERSION="${INITIAL_VERSION:-}"
TAG_PREFIX="${TAG_PREFIX:-v}"
PROJECT_DIR="${PROJECT_DIR:-.}"
RUN_NUMBER="${GITHUB_RUN_NUMBER:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "::error::$*" >&2; exit 1; }

case "$MODE" in release | preview | ci) ;; *) die "mode invalide : $MODE" ;; esac
case "$BUMP" in auto | patch | minor | major) ;; *) die "bump invalide : $BUMP" ;; esac

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

is_semver() { [[ "$1" =~ $SEMVER_RE ]]; }

# bump_version 1.4.2 minor -> 1.5.0
bump_version() {
  local major minor patch
  IFS=. read -r major minor patch <<<"$1"
  case "$2" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

# Bump déduit des commits d'une plage git (Conventional Commits).
detect_bump() {
  local range="$1" log
  log="$(git log --format='%B' "$range")"
  if grep -Eq '^[a-zA-Z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$log"; then
    echo major
  elif grep -Eq '^feat(\([^)]*\))?:' <<<"$log"; then
    echo minor
  else
    echo patch
  fi
}

# Dernier tag de release (X.Y.Z strict) atteignable depuis HEAD.
previous_tag=""
while IFS= read -r t; do
  if is_semver "${t#"$TAG_PREFIX"}"; then
    previous_tag="$t"
    break
  fi
done < <(git tag --merged HEAD --list "${TAG_PREFIX}*" --sort=-v:refname)

exists=false
if [ -n "$previous_tag" ]; then
  current="${previous_tag#"$TAG_PREFIX"}"
  if [ "$(git rev-list -n 1 "$previous_tag")" = "$(git rev-parse HEAD)" ]; then
    # HEAD est déjà releasé : relance d'un run, on réutilise la même version.
    exists=true
    release_version="$current"
    applied="none"
  else
    applied="$BUMP"
    [ "$applied" = auto ] && applied="$(detect_bump "$previous_tag..HEAD")"
    release_version="$(bump_version "$current" "$applied")"
  fi
else
  # Aucun tag : première release.
  if [ -n "$INITIAL_VERSION" ]; then
    is_semver "$INITIAL_VERSION" || die "initial-version doit être de la forme X.Y.Z : $INITIAL_VERSION"
    release_version="$INITIAL_VERSION"
    applied="initial"
  else
    seed="$(python3 "$SCRIPT_DIR/read-project-version.py" "$PROJECT_DIR")"
    base="${seed%%-*}"
    if ! is_semver "$base" || [ "$base" = "0.0.0" ]; then
      # Rien d'exploitable (ou placeholder) : on démarre à 0.1.0.
      release_version="0.1.0"
      applied="initial"
    elif [ "$seed" != "$base" ]; then
      # 1.0.13-SNAPSHOT : la prochaine release est 1.0.13.
      release_version="$base"
      applied="initial"
    else
      # 1.4.2 déjà publiée : on bumpe.
      applied="$BUMP"
      [ "$applied" = auto ] && applied="patch"
      release_version="$(bump_version "$base" "$applied")"
    fi
  fi
fi

case "$MODE" in
  release) version="$release_version" ;;
  preview) version="$release_version-rc.$RUN_NUMBER" ;;
  ci) version="$release_version-ci.$(git rev-parse --short=7 HEAD)" ;;
esac

{
  echo "version=$version"
  echo "release-version=$release_version"
  echo "tag=$TAG_PREFIX$release_version"
  echo "previous-tag=$previous_tag"
  echo "bump=$applied"
  echo "exists=$exists"
} | tee -a "${GITHUB_OUTPUT:-/dev/null}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "**Version** \`$version\` (précédente : \`${previous_tag:-aucune}\`, bump : $applied)" >>"$GITHUB_STEP_SUMMARY"
fi
