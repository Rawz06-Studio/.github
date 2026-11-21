# ghcr.io/rawz06-studio/php-runtime:8.4
#
# FrankenPHP : un seul binaire qui sert le HTTP et exécute PHP (pas de nginx + php-fpm).
#
# Usage dans un projet (vendor/ installé par la CI avec `composer install --no-dev`) :
#   FROM ghcr.io/rawz06-studio/php-runtime:8.4
#   COPY --chown=app:app . /app
#
# La racine web est /app/public. Le serveur écoute en HTTP sur le port 8080 ;
# le TLS est géré en amont (Dokploy / Traefik).
#
# Extensions en plus ?
#   USER root
#   RUN install-php-extensions redis
#   USER 10001:10001

FROM dunglas/frankenphp:1-php8.4-trixie

RUN apt-get update \
    && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && install-php-extensions intl opcache pdo_pgsql pgsql zip \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /app/public \
    && chown -R app:app /app /config/caddy /data/caddy

COPY php.ini "$PHP_INI_DIR/conf.d/zz-rawz06.ini"

WORKDIR /app

# SERVER_NAME sans nom d'hôte = HTTP simple sur ce port, sans certificat automatique.
ENV TZ=Europe/Paris \
    SERVER_NAME=":8080"

USER 10001:10001

EXPOSE 8080
