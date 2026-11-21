# ghcr.io/rawz06-studio/static-web:latest
#
# nginx non-root (port 8080) pour sites statiques.
#
# Usage dans un projet :
#   FROM ghcr.io/rawz06-studio/static-web:latest
#   COPY dist/ /usr/share/nginx/html/
#
# Application monopage (Vue, React…) : renvoyer index.html pour les routes inconnues.
#   ENV NGINX_FALLBACK=/index.html
#
# Configuration entièrement personnalisée : remplacer /etc/nginx/templates/default.conf.template.

FROM nginxinc/nginx-unprivileged:stable-alpine

USER root
RUN apk add --no-cache tzdata && rm -f /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx default.conf.template /etc/nginx/templates/default.conf.template
USER 101:101

ENV TZ=Europe/Paris \
    NGINX_FALLBACK="=404"

EXPOSE 8080
