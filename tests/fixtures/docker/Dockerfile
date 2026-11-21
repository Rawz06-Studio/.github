# Image de test construite directement depuis le repo, avec l'argument APP_VERSION.
FROM busybox:musl
ARG APP_VERSION=dev
RUN echo "fixture ${APP_VERSION}" > /version
CMD ["cat", "/version"]
