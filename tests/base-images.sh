#!/usr/bin/env bash
# Tests fonctionnels des images de base, construites localement sous local/<nom>:test.
#
#   for n in $(jq -r '.[].name' images/images.json); do
#     docker build -t "local/${n}:test" "images/${n}"
#   done
#   tests/base-images.sh                 # toutes les images
#   tests/base-images.sh static-web      # une seule
#
# Nécessite docker et curl. Les ports 18081 à 18085 doivent être libres.
set -uo pipefail

WORK="$(mktemp -d)"
CONTAINERS=()
cleanup() {
  [ "${#CONTAINERS[@]}" -gt 0 ] && docker rm -f "${CONTAINERS[@]}" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

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

# Lance un conteneur en arrière-plan et attend qu'il réponde sur l'URL donnée.
serve() {
  local url="$1"; shift
  local id
  id="$(docker run -d "$@")" || return 1
  CONTAINERS+=("$id")
  for _ in $(seq 1 40); do
    curl -fs -o /dev/null "$url" && { echo "$id"; return 0; }
    sleep 0.5
  done
  echo "le conteneur ne répond pas sur $url" >&2
  docker logs "$id" >&2
  echo "$id"
}

# --- java-runtime ---------------------------------------------------------------
test_java_runtime() {
  mkdir -p "$WORK/java"
  cat >"$WORK/java/Main.java" <<'EOF'
public class Main {
  public static void main(String[] args) {
    System.out.println("hello " + String.join(",", args)
      + " user=" + System.getProperty("user.name")
      + " tz=" + java.util.TimeZone.getDefault().getID()
      + " profile=" + System.getenv("SPRING_PROFILES_ACTIVE"));
  }
}
EOF
  docker run --rm -v "$WORK/java:/src" -w /src eclipse-temurin:25-jdk \
    sh -c 'javac Main.java && printf "Main-Class: Main\n" > m.txt && jar cfm app.jar m.txt Main.class' >/dev/null
  out="$(docker run --rm -v "$WORK/java/app.jar:/app/app.jar:ro" local/java-runtime:test a b 2>&1)"
  check "java : lance /app/app.jar" "$out" "hello a,b"
  check "java : utilisateur non-root" "$out" "user=app"
  check "java : fuseau horaire" "$out" "tz=Europe/Paris"
  check "java : profil Spring prod" "$out" "profile=prod"
  out="$(docker run --rm --entrypoint id local/java-runtime:test)"
  check "java : uid 10001" "$out" "uid=10001(app)"
}

# --- node-runtime ---------------------------------------------------------------
test_node_runtime() {
  mkdir -p "$WORK/node"
  cat >"$WORK/node/server.mjs" <<'EOF'
import http from "node:http";
import os from "node:os";
http.createServer((_, res) => {
  res.end(`env=${process.env.NODE_ENV} user=${os.userInfo().username} pid=${process.pid}`);
}).listen(process.env.PORT, process.env.HOST);
EOF
  id="$(serve http://127.0.0.1:18082 -p 127.0.0.1:18082:3000 \
    -v "$WORK/node/server.mjs:/app/server.mjs:ro" local/node-runtime:test node server.mjs)"
  out="$(curl -s http://127.0.0.1:18082)"
  check "node : sert sur PORT/HOST" "$out" "env=production"
  check "node : utilisateur node" "$out" "user=node"
  out="$(docker exec "$id" cat /proc/1/cmdline | tr '\0' ' ')"
  check "node : tini en PID 1" "$out" "tini"
  local start elapsed
  start=$SECONDS
  docker stop -t 10 "$id" >/dev/null
  elapsed=$((SECONDS - start))
  # Sans tini, Node ignore SIGTERM en PID 1 et docker attend les 10 s avant SIGKILL.
  check "node : arrêt rapide sur SIGTERM (${elapsed}s)" "$([ "$elapsed" -lt 5 ] && echo rapide || echo lent)" "rapide"
}

# --- php-runtime ----------------------------------------------------------------
test_php_runtime() {
  mkdir -p "$WORK/php/public"
  cat >"$WORK/php/public/index.php" <<'EOF'
<?php
echo 'php=' . PHP_VERSION
  . ' user=' . posix_getpwuid(posix_geteuid())['name']
  . ' pgsql=' . (extension_loaded('pdo_pgsql') ? 'yes' : 'no')
  . ' opcache=' . (extension_loaded('Zend OPcache') ? 'yes' : 'no')
  . ' tz=' . date_default_timezone_get();
EOF
  serve http://127.0.0.1:18083 -p 127.0.0.1:18083:8080 \
    -v "$WORK/php/public:/app/public:ro" local/php-runtime:test >/dev/null
  out="$(curl -s http://127.0.0.1:18083/)"
  check "php : PHP 8.4 servi par FrankenPHP" "$out" "php=8.4"
  check "php : utilisateur non-root" "$out" "user=app"
  check "php : pdo_pgsql" "$out" "pgsql=yes"
  check "php : opcache" "$out" "opcache=yes"
  check "php : fuseau horaire" "$out" "tz=Europe/Paris"
  out="$(curl -sI http://127.0.0.1:18083/)"
  check "php : X-Powered-By masqué" "$(grep -ci 'x-powered-by' <<<"$out" || true)" "0"
}

# --- rust-runtime ---------------------------------------------------------------
test_rust_runtime() {
  # busybox:musl est un binaire statique, comme un binaire Rust musl.
  docker run --rm -v "$WORK:/out" busybox:musl cp /bin/busybox /out/busybox
  out="$(docker run --rm -v "$WORK/busybox:/app/busybox:ro" local/rust-runtime:test /app/busybox id)"
  check "rust : uid 10001" "$out" "uid=10001(app)"
  out="$(docker run --rm -v "$WORK/busybox:/app/busybox:ro" local/rust-runtime:test /app/busybox date +%Z)"
  check "rust : fuseau horaire" "$out" "CE"
  out="$(docker run --rm -v "$WORK/busybox:/app/busybox:ro" local/rust-runtime:test /app/busybox touch /app/x /tmp/x && echo writable)"
  check "rust : /app et /tmp en écriture" "$out" "writable"
  out="$(docker run --rm local/rust-runtime:test /bin/sh -c true 2>&1)"
  check "rust : pas de shell" "$out" "no such file"
  out="$(docker run --rm -v "$WORK/busybox:/app/busybox:ro" local/rust-runtime:test /app/busybox ls /etc/ssl/certs)"
  check "rust : certificats CA" "$out" "ca-certificates.crt"
}

# --- static-web -----------------------------------------------------------------
test_static_web() {
  mkdir -p "$WORK/web/assets"
  echo '<h1>accueil</h1>' >"$WORK/web/index.html"
  head -c 4000 /dev/zero | tr '\0' 'a' >"$WORK/web/assets/app-abc123.js"
  serve http://127.0.0.1:18085/healthz -p 127.0.0.1:18085:8080 \
    -v "$WORK/web:/usr/share/nginx/html:ro" local/static-web:test >/dev/null
  check "static : page d'accueil" "$(curl -s http://127.0.0.1:18085/)" "accueil"
  check "static : healthz" "$(curl -s http://127.0.0.1:18085/healthz)" "ok"
  check "static : HTML revalidé" "$(curl -sI http://127.0.0.1:18085/)" "Cache-Control: no-cache"
  headers="$(curl -sI -H 'Accept-Encoding: gzip' http://127.0.0.1:18085/assets/app-abc123.js)"
  check "static : assets immuables" "$headers" "immutable"
  check "static : gzip" "$headers" "Content-Encoding: gzip"
  check "static : nosniff" "$headers" "X-Content-Type-Options: nosniff"
  check "static : version nginx masquée" "$(curl -sI http://127.0.0.1:18085/)" "Server: nginx"$'\r'
  check "static : 404 par défaut" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18085/route/inconnue)" "404"

  serve http://127.0.0.1:18084/healthz -p 127.0.0.1:18084:8080 -e NGINX_FALLBACK=/index.html \
    -v "$WORK/web:/usr/share/nginx/html:ro" local/static-web:test >/dev/null
  check "static : fallback SPA" "$(curl -s http://127.0.0.1:18084/route/inconnue)" "accueil"
  check "static : asset manquant reste en 404" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18084/assets/absent.js)" "404"
}

images=("$@")
[ "${#images[@]}" -gt 0 ] || images=(java-runtime node-runtime php-runtime rust-runtime static-web)
for image in "${images[@]}"; do
  fn="test_${image//-/_}"
  if declare -F "$fn" >/dev/null; then
    "$fn"
  else
    echo "FAIL - aucun test pour l'image $image"
    count=$((count + 1))
    failures=$((failures + 1))
  fi
done

echo
echo "$((count - failures))/$count tests OK"
[ "$failures" -eq 0 ]
