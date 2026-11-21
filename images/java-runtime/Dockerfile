# ghcr.io/rawz06-studio/java-runtime:25
#
# Usage dans un projet :
#   FROM ghcr.io/rawz06-studio/java-runtime:25
#   COPY app.jar /app/app.jar
#
# Besoin de paquets système en plus ? Repasser root le temps de l'installation :
#   USER root
#   RUN apt-get update && apt-get install -y --no-install-recommends ... && rm -rf /var/lib/apt/lists/*
#   USER 10001:10001

FROM eclipse-temurin:25-jre-noble

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /app \
    && chown app:app /app

WORKDIR /app

ENV TZ=Europe/Paris \
    JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError" \
    SPRING_PROFILES_ACTIVE=prod

USER 10001:10001

EXPOSE 8080

# `exec` : Java devient PID 1 et reçoit SIGTERM (arrêt propre de Spring).
# Les arguments passés au conteneur sont transmis à l'application.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar \"$@\"", "--"]
