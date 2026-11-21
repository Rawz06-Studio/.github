# ghcr.io/rawz06-studio/node-runtime:24
#
# Usage dans un projet (Nuxt) :
#   FROM ghcr.io/rawz06-studio/node-runtime:24
#   COPY --chown=node:node .output ./.output
#   CMD ["node", ".output/server/index.mjs"]
#
# Debian (et pas Alpine) : les modules natifs compilés par la CI dans node:24-trixie
# tournent sur la même libc.
#
# Besoin de paquets système en plus (ffmpeg…) ?
#   USER root
#   RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
#   USER 1000:1000

FROM node:24-trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app \
    && chown node:node /app

WORKDIR /app

ENV TZ=Europe/Paris \
    NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000

USER 1000:1000

EXPOSE 3000

# tini relaie les signaux et récupère les processus zombies : Node n'est pas fait pour être PID 1.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "--version"]
