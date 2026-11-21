# Rawz06-Studio / .github

Workflows CI/CD partagés, actions composites et images de base des projets Rawz06-Studio.

> **Refonte en cours.** La cible est décrite dans [ARCHITECTURE.md](ARCHITECTURE.md).
> Les projets non migrés utilisent toujours les anciens workflows documentés dans [USE.md](USE.md).

## Contenu

| Dossier | Rôle |
|---|---|
| [`actions/`](actions) | Actions composites (setup, version, déploiement) |
| [`images/`](images) | Images de base publiées sur GHCR |
| [`.github/workflows/`](.github/workflows) | Jobs réutilisables (`_*.yml`) et pipelines par profil |
| [`tests/`](tests) | Tests des scripts et des images |

## Utiliser dans un projet

Un seul fichier, `.github/workflows/pipeline.yml`, créé depuis *Actions → New workflow*
(modèles « Rawz06 · … » de [`workflow-templates/`](workflow-templates)) :

| Pipeline | Pour | Modèle |
|---|---|---|
| [`java-app`](.github/workflows/java-app.yml) | application Java en image Docker | [java-app.yml](workflow-templates/java-app.yml) |
| [`java-lib`](.github/workflows/java-lib.yml) | bibliothèque Maven sur GitHub Packages | [java-lib.yml](workflow-templates/java-lib.yml) |
| [`node-app`](.github/workflows/node-app.yml) | Nuxt, serveur Node, front buildé | [node-app.yml](workflow-templates/node-app.yml) |
| [`php-app`](.github/workflows/php-app.yml) | application PHP (FrankenPHP) | [php-app.yml](workflow-templates/php-app.yml) |
| [`rust-app`](.github/workflows/rust-app.yml) | serveur Rust (musl) + client WASM | [rust-app.yml](workflow-templates/rust-app.yml) |
| [`rust-desktop`](.github/workflows/rust-desktop.yml) | application desktop, binaires multi-plateformes | [rust-desktop.yml](workflow-templates/rust-desktop.yml) |
| [`docker-app`](.github/workflows/docker-app.yml) | le Dockerfile fait tout | [docker-app.yml](workflow-templates/docker-app.yml) |

| Événement | Mode | Résultat |
|---|---|---|
| PR, push sur une branche | `ci` | tests, image construite et testée, rien de publié |
| PR avec le label `preview` | `preview` | image `:preview` publiée, déploiement preprod |
| push sur la branche par défaut | `release` | image `:<version>`, tag + GitHub Release, déploiement prod |
| *Run workflow* | au choix | release ou preview, bump `patch` / `minor` / `major` forcé |

Secrets du projet : `DOKPLOY_WEBHOOK`, la « Webhook URL » de l'app de prod copiée depuis Dokploy,
et `DOKPLOY_PREVIEW_WEBHOOK` pour l'app de preprod (facultatif).

### Actions disponibles

| Action | Rôle |
|---|---|
| [`compute-version`](actions/compute-version/action.yml) | Calcule la prochaine version depuis les tags et les Conventional Commits |
| [`set-version`](actions/set-version/action.yml) | Injecte la version dans le workspace : `.mvn/maven.config` (pom en `${revision}`), `package.json`, `Cargo.toml` + `Cargo.lock`, `VERSION` (PHP) |
| [`setup-java`](actions/setup-java/action.yml) | JDK (25 par défaut), cache Maven, accès GitHub Packages ; sortie `mvn` (`./mvnw` si présent) |
| [`setup-node`](actions/setup-node/action.yml) | pnpm (`packageManager`), Node (`.nvmrc` ou 24), cache, registre `@rawz06-studio`, `pnpm install --frozen-lockfile` |
| [`setup-php`](actions/setup-php/action.yml) | PHP 8.4 avec les extensions de `php-runtime`, Composer, cache, `composer install` |
| [`setup-rust`](actions/setup-rust/action.yml) | Toolchain (`rust-toolchain.toml` ou stable), targets, composants, paquets apt, musl-tools, cache |
| [`dokploy-deploy`](actions/dokploy-deploy/action.yml) | Appelle le webhook Dokploy de l'application, URL masquée, 3 relances |
| [`resolve-mode`](actions/resolve-mode/action.yml) | Déduit le mode du run de l'événement (`release`, `preview`, `ci`) et le bump demandé |
| [`prepare-image-context`](actions/prepare-image-context/action.yml) | Archive le Dockerfile et les fichiers du build (permissions et fichiers cachés conservés) en artefact pour `_docker` |

Les étapes Maven qui lisent GitHub Packages définissent `MAVEN_USERNAME: ${{ github.actor }}` et
`MAVEN_PASSWORD: ${{ github.token }}` dans leur `env:` : le jeton n'est jamais écrit sur le disque.

### Jobs réutilisables

Briques des pipelines ; un projet ne les appelle directement que pour un besoin particulier.

| Job | Rôle | Permissions à accorder |
|---|---|---|
| [`_version`](.github/workflows/_version.yml) | Mode du run (`auto` = déduit de l'événement) et version | `contents: read` |
| [`_java`](.github/workflows/_java.yml) | `mvn verify`, publication GitHub Packages (`publish`), contexte d'image (`app.jar`) | `contents: read`, `packages: read` (`write` si `publish`) |
| [`_node`](.github/workflows/_node.yml) | Scripts `lint typecheck test build`, dépendances de prod (modules natifs dans `node:<v>-trixie`), contexte d'image | `contents: read`, `packages: read` |
| [`_php`](.github/workflows/_php.yml) | Composer, tests, `vendor/` de prod + `VERSION`, contexte d'image | `contents: read` |
| [`_rust`](.github/workflows/_rust.yml) | fmt, clippy, tests ; binaires musl dans `bin/` et client WASM (trunk) pour l'image | `contents: read` |
| [`_rust-binaries`](.github/workflows/_rust-binaries.yml) | Binaires par plateforme (matrice JSON, macOS universel), scripts `scripts/package-*` du projet ou archive | `contents: read` |
| [`_docker`](.github/workflows/_docker.yml) | Image depuis le contexte (ou le repo), test optionnel, push GHCR avec les tags du mode | `contents: read` (+ `packages: write` pour publier) |
| [`_release`](.github/workflows/_release.yml) | Tag + GitHub Release, artefacts attachés + `SHA256SUMS`, idempotent | `contents: write` |
| [`_deploy`](.github/workflows/_deploy.yml) | Déploiement Dokploy dans un environnement GitHub ; sans jeton, ne fait rien | `contents: read` |

Chaque job récupère les actions de ce repo dans `.rawz06-ci/` à la ref `tooling-ref` (défaut `v1`).
`_java` et `_docker` ne déclarent pas de permissions et héritent de celles de l'appelant :
GitHub vérifie les permissions d'un job réutilisable sans tenir compte des `if:`.

### Images de base

Publiées sur `ghcr.io/rawz06-studio/<image>` pour `linux/amd64` et `linux/arm64`, reconstruites
chaque lundi. Chaque image a un tag mobile et un tag daté figé (ex. `java-runtime:25-2026.11.21`).

| Image | Utilisateur | Port | Le projet ajoute |
|---|---|---|---|
| [`java-runtime:25`](images/java-runtime/Dockerfile) | `10001` | 8080 | `COPY app.jar /app/app.jar` |
| [`node-runtime:24`](images/node-runtime/Dockerfile) | `1000` (node) | 3000 | ses fichiers + `CMD ["node", "…"]` |
| [`php-runtime:8.4`](images/php-runtime/Dockerfile) | `10001` | 8080 | `COPY . /app` (racine web : `/app/public`) |
| [`rust-runtime`](images/rust-runtime/Dockerfile) | `10001` | — | binaire musl + `CMD ["/app/…"]` |
| [`static-web`](images/static-web/Dockerfile) | `101` (nginx) | 8080 | `COPY dist/ /usr/share/nginx/html/` |

Communs : fuseau `Europe/Paris`, aucun processus en root. `static-web` expose `/healthz` et
accepte `NGINX_FALLBACK=/index.html` pour les applications monopage.

## Versions de ce repo

Chaque push sur `main` publie une release (`vX.Y.Z`). À partir de la 1.0.0, le tag majeur
(`v1`) suit la dernière release : les projets référencent `@v1`.

| Commit | Effet |
|---|---|
| `fix: …`, `chore: …`, autre | patch |
| `feat: …` | minor |
| `feat!: …` ou `BREAKING CHANGE:` | major |

## Développer

```bash
tests/compute-version.sh
```

```bash
tests/set-version.sh
```

```bash
tests/dokploy-deploy.sh
```

```bash
tests/resolve-mode.sh
```

```bash
tests/prepare-image-context.sh
```

Mini-projets de `tests/fixtures/` (Maven, pnpm, Composer et Cargo installés en local) :

```bash
tests/fixtures.sh
```

Images de base (Docker requis) :

```bash
for n in $(jq -r '.[].name' images/images.json); do docker build -t "local/${n}:test" "images/${n}"; done
```

```bash
tests/base-images.sh
```

En CI, `self-test.yml` lance aussi actionlint, zizmor, hadolint, shellcheck, chaque action `setup-*` sur sa fixture,
et chaque pipeline de bout en bout en mode `ci` (build, image lancée et vérifiée) sans rien publier ;
`base-images.yml` reconstruit et teste chaque image sur les deux architectures.
