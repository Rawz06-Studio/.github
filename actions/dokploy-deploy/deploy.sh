#!/usr/bin/env bash
# Déclenche un déploiement Dokploy en appelant le webhook de l'application,
# la méthode recommandée par Dokploy pour redéployer depuis une CI.
#
# Variables d'entrée :
#   DOKPLOY_WEBHOOK_URL    URL du webhook, copiée depuis Dokploy
#                          (https://<instance>/api/deploy/<jeton>) — secret
#   DOKPLOY_RETRY_DELAY    secondes entre deux essais (défaut : 5)
#
# L'URL contient le jeton : elle n'est jamais affichée, seul l'hôte apparaît.
set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

url="${DOKPLOY_WEBHOOK_URL:-}"
url="${url%/}"
[ -n "$url" ] || die "URL du webhook Dokploy manquante"
echo "::add-mask::$url"

if ! [[ "$url" =~ ^https?://([^/]+)/api/deploy/([^/?#]+)$ ]]; then
  die "URL de webhook Dokploy invalide : attendu https://<instance>/api/deploy/<jeton>"
fi
host="${BASH_REMATCH[1]}"
echo "::add-mask::${BASH_REMATCH[2]}"

echo "Déploiement via le webhook de $host"
curl --silent --show-error --fail-with-body \
  --connect-timeout 10 --max-time 60 \
  --retry 3 --retry-delay "${DOKPLOY_RETRY_DELAY:-5}" --retry-all-errors \
  -X GET "$url"
echo
echo "Déploiement déclenché."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Déploiement Dokploy déclenché sur \`$host\`" >>"$GITHUB_STEP_SUMMARY"
fi
