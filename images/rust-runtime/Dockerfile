# ghcr.io/rawz06-studio/rust-runtime:latest
#
# Image minimale (FROM scratch) pour un binaire Rust compilé en statique
# (target x86_64-unknown-linux-musl). Pas de shell, pas de gestionnaire de paquets.
#
# Usage dans un projet :
#   FROM ghcr.io/rawz06-studio/rust-runtime:latest
#   COPY tracker-server /app/tracker-server
#   CMD ["/app/tracker-server"]
#
# Fichiers en écriture : /app appartient à l'utilisateur app (uid 10001).

FROM debian:trixie-slim AS rootfs

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && mkdir -p /rootfs/etc/ssl/certs /rootfs/usr/share /rootfs/app /rootfs/tmp \
    && cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/ \
    && cp -r /usr/share/zoneinfo /rootfs/usr/share/zoneinfo \
    && echo 'app:x:10001:10001:app:/app:/sbin/nologin' > /rootfs/etc/passwd \
    && echo 'app:x:10001:' > /rootfs/etc/group \
    && chown 10001:10001 /rootfs/app \
    && chmod 1777 /rootfs/tmp

FROM scratch

COPY --from=rootfs /rootfs /

WORKDIR /app

ENV TZ=Europe/Paris \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

USER 10001:10001
