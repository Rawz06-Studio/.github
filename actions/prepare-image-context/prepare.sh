#!/usr/bin/env bash
# Crée $RUNNER_TEMP/image-context.tar à partir du dossier courant.
#
# Variables d'entrée :
#   DOCKERFILE   chemin du Dockerfile (copié en ./Dockerfile dans le contexte)
#   FILES        chemins à embarquer, un par ligne ; lignes vides et # ignorées
#   RUNNER_TEMP  dossier de sortie (fourni par GitHub Actions)
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

out="${RUNNER_TEMP:?}/image-context.tar"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

[ -f "$DOCKERFILE" ] || die "Dockerfile introuvable : $DOCKERFILE"

paths=()
while IFS= read -r line; do
  path="$(sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$line")"
  [ -n "$path" ] || continue
  case "$path" in
    /* | ../* | */../* | ..) die "chemin hors du projet interdit : $path" ;;
  esac
  [ -e "$path" ] || die "fichier à embarquer introuvable : $path"
  paths+=("$path")
done <<<"${FILES:-}"
[ "${#paths[@]}" -gt 0 ] || die "aucun fichier à embarquer (input files)"

# tar conserve l'arborescence, les permissions (binaires exécutables) et les fichiers cachés (.output).
# .rawz06-ci est le checkout des actions partagées fait par les jobs : jamais dans l'image.
tar -cf - --exclude=.git --exclude=.rawz06-ci "${paths[@]}" | tar -xf - -C "$staging"
cp "$DOCKERFILE" "$staging/Dockerfile"
if [ -f .dockerignore ]; then
  cp .dockerignore "$staging/.dockerignore"
fi

tar -cf "$out" -C "$staging" .
echo "Contexte Docker :"
tar -tvf "$out" | awk '{print "  " $NF}' | grep -v '/$' | head -50
echo "Taille : $(du -h "$out" | cut -f1)"
