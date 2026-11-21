#!/usr/bin/env bash
# Déclenche un déploiement Dokploy.
#
# Variables d'entrée :
#   DOKPLOY_URL              URL de l'instance (obligatoire)
#   DOKPLOY_WEBHOOK_TOKEN    jeton du webhook de l'application        -> GET  <url>/api/deploy/<jeton>
#   DOKPLOY_API_KEY          clé d'API, avec DOKPLOY_APPLICATION_ID    -> POST <url>/api/application.deploy
#   DOKPLOY_RETRY_DELAY      secondes entre deux essais (défaut : 5)
#
# Les jetons ne sont jamais affichés.
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

url="${DOKPLOY_URL:-}"
url="${url%/}"
[ -n "$url" ] || die "url Dokploy manquante"
[[ "$url" =~ ^https?:// ]] || die "url Dokploy invalide : $url"

webhook="${DOKPLOY_WEBHOOK_TOKEN:-}"
api_key="${DOKPLOY_API_KEY:-}"
app_id="${DOKPLOY_APPLICATION_ID:-}"

for secret in "$webhook" "$api_key"; do
  [ -n "$secret" ] && echo "::add-mask::$secret"
done

curl_args=(
  --silent --show-error --fail-with-body
  --connect-timeout 10 --max-time 60
  --retry 3 --retry-delay "${DOKPLOY_RETRY_DELAY:-5}" --retry-all-errors
)

if [ -n "$api_key" ]; then
  [ -z "$webhook" ] || die "webhook-token et api-key sont exclusifs"
  [ -n "$app_id" ] || die "application-id est obligatoire avec api-key"
  echo "Déploiement de l'application $app_id via l'API ($url)"
  # La clé passe par un fichier d'en-têtes pour ne pas apparaître dans la ligne de commande.
  headers="$(mktemp)"
  trap 'rm -f "$headers"' EXIT
  printf 'x-api-key: %s\nContent-Type: application/json\n' "$api_key" >"$headers"
  body="$(printf '{"applicationId":"%s"}' "$app_id")"
  curl "${curl_args[@]}" -X POST -H "@$headers" --data "$body" "$url/api/application.deploy"
elif [ -n "$webhook" ]; then
  [ -z "$app_id" ] || die "application-id ne s'utilise qu'avec api-key"
  echo "Déploiement via le webhook ($url)"
  curl "${curl_args[@]}" -X GET "$url/api/deploy/$webhook"
else
  die "fournir webhook-token, ou api-key + application-id"
fi
echo
echo "Déploiement déclenché."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Déploiement Dokploy déclenché sur \`$url\`" >>"$GITHUB_STEP_SUMMARY"
fi
