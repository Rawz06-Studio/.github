#!/usr/bin/env bash
# Tests de actions/dokploy-deploy/deploy.sh contre un faux serveur Dokploy local.
# Usage : tests/dokploy-deploy.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/actions/dokploy-deploy/deploy.sh"
WORK="$(mktemp -d)"
LOG="$WORK/requests.log"

# Faux Dokploy : journalise chaque requête ; un jeton ou un id contenant "fail" renvoie 500.
cat >"$WORK/server.py" <<'EOF'
import http.server, json, sys

log = open(sys.argv[1], "a", buffering=1)

class Handler(http.server.BaseHTTPRequestHandler):
    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        log.write(json.dumps({"method": self.command, "path": self.path,
                              "key": self.headers.get("x-api-key"), "body": body}) + "\n")
        status = 500 if "fail" in self.path + body else 200
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
URL="http://127.0.0.1:$(cat "$WORK/port")"

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

run DOKPLOY_URL="$URL/" DOKPLOY_WEBHOOK_TOKEN=abc123
check "webhook : succès" "$STATUS" "0"
check "webhook : GET sur /api/deploy/<jeton>" "$REQUESTS" '"method": "GET", "path": "/api/deploy/abc123"'
check "webhook : jeton masqué" "$OUT" "::add-mask::abc123"
check "webhook : jeton absent du reste de la sortie" "$(grep -v add-mask <<<"$OUT" | grep -c abc123)" "0"

run DOKPLOY_URL="$URL" DOKPLOY_API_KEY=key42 DOKPLOY_APPLICATION_ID=app-1
check "api : succès" "$STATUS" "0"
check "api : POST /api/application.deploy" "$REQUESTS" '"method": "POST", "path": "/api/application.deploy"'
check "api : clé en en-tête" "$REQUESTS" '"key": "key42"'
check "api : corps JSON" "$REQUESTS" '{\"applicationId\":\"app-1\"}'

run DOKPLOY_URL="$URL" DOKPLOY_WEBHOOK_TOKEN=fail
check "erreur serveur : échec" "$STATUS" "22"
check "erreur serveur : 4 essais (1 + 3 relances)" "$(wc -l <<<"$REQUESTS" | tr -d ' ')" "4"
check "erreur serveur : corps de la réponse affiché" "$OUT" "boom"

run DOKPLOY_URL="$URL"
check "aucun identifiant : erreur" "$OUT" "fournir webhook-token"

run DOKPLOY_URL="$URL" DOKPLOY_API_KEY=k
check "api sans application-id : erreur" "$OUT" "application-id est obligatoire"

run DOKPLOY_URL="$URL" DOKPLOY_API_KEY=k DOKPLOY_APPLICATION_ID=a DOKPLOY_WEBHOOK_TOKEN=t
check "webhook + api : erreur" "$OUT" "exclusifs"

run DOKPLOY_URL="dokploy.example.com" DOKPLOY_WEBHOOK_TOKEN=t
check "url sans schéma : erreur" "$OUT" "url Dokploy invalide"

run DOKPLOY_WEBHOOK_TOKEN=t
check "url manquante : erreur" "$OUT" "url Dokploy manquante"

check "aucune requête sur les erreurs de configuration" "$(grep -c . <<<"$REQUESTS")" "0"

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
