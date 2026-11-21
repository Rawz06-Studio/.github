#!/usr/bin/env bash
# Tests de actions/dokploy-deploy/deploy.sh contre un faux serveur Dokploy local.
# Usage : tests/dokploy-deploy.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/dokploy-deploy/deploy.sh"
WORK="$(mktemp -d)"
LOG="$WORK/requests.log"

# Faux Dokploy : journalise chaque requête ; un jeton contenant "fail" renvoie 500.
cat >"$WORK/server.py" <<'EOF'
import http.server, json, sys

log = open(sys.argv[1], "a", buffering=1)

class Handler(http.server.BaseHTTPRequestHandler):
    def handle_any(self):
        log.write(json.dumps({"method": self.command, "path": self.path}) + "\n")
        status = 500 if "fail" in self.path else 200
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}' if status == 200 else b'{"error":"boom"}')
    do_GET = do_POST = handle_any
    def log_message(self, *args): pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
EOF
python3 "$WORK/server.py" "$LOG" >"$WORK/port" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
BASE="http://127.0.0.1:$(cat "$WORK/port")"

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

run() {
  : >"$LOG"
  OUT="$(env -u GITHUB_STEP_SUMMARY DOKPLOY_RETRY_DELAY=0 "$@" bash "$SCRIPT" 2>&1)"
  STATUS=$?
  REQUESTS="$(cat "$LOG")"
}

run DOKPLOY_WEBHOOK_URL="$BASE/api/deploy/abc123/"
check "webhook : succès" "$STATUS" "0"
check "webhook : GET sur /api/deploy/<jeton>" "$REQUESTS" '"method": "GET", "path": "/api/deploy/abc123"'
check "webhook : URL masquée" "$OUT" "::add-mask::$BASE/api/deploy/abc123"
check "webhook : jeton masqué" "$OUT" "::add-mask::abc123"
check "webhook : seul l'hôte est affiché" "$OUT" "Déploiement via le webhook de 127.0.0.1:"
check "webhook : jeton absent du reste de la sortie" "$(grep -v add-mask <<<"$OUT" | grep -c abc123)" "0"

run DOKPLOY_WEBHOOK_URL="$BASE/api/deploy/fail"
check "erreur serveur : échec" "$STATUS" "22"
check "erreur serveur : 4 essais (1 + 3 relances)" "$(wc -l <<<"$REQUESTS" | tr -d ' ')" "4"
check "erreur serveur : corps de la réponse affiché" "$OUT" "boom"

run
check "URL manquante : erreur" "$OUT" "URL du webhook Dokploy manquante"

run DOKPLOY_WEBHOOK_URL="$BASE/api/application.deploy"
check "URL qui n'est pas un webhook : erreur" "$OUT" "URL de webhook Dokploy invalide"

run DOKPLOY_WEBHOOK_URL="dokploy.example.com/api/deploy/abc"
check "URL sans schéma : erreur" "$OUT" "URL de webhook Dokploy invalide"

check "aucune requête sur les erreurs de configuration" "$(grep -c . <<<"$REQUESTS")" "0"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
