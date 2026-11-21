# Image de test : vérifie que les fichiers produits par le build arrivent dans l'image.
FROM node:24-trixie-slim
COPY dist /app/dist
CMD ["cat", "/app/dist/version.txt"]
