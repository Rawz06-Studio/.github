# Architecture CI/CD — Rawz06-Studio

Ce document décrit la cible. Il sert de référence pour la refonte du repo `.github`
et la migration des projets. `USE.md` sera remplacé par la doc d'utilisation une fois
les pipelines en place.

---

## 1. Principes

1. **Push sur `main` = publication.** Chaque push sur `main` produit une version, la publie et la déploie.
2. **La CI ne committe jamais.** La version vient des tags git ; elle est injectée dans le workspace au moment du build.
3. **On build une seule fois.** La CI compile et teste ; l'image Docker ne fait que copier le résultat sur une image de base maison.
4. **Ce qui part en prod est ce qui a été testé.** Même commit, même artefact.
5. **Aucune duplication.** Setup = action composite, job = workflow réutilisable, pipeline = assemblage de jobs.
6. **Rien en dur.** Ni org, ni domaine, ni token dans les YAML ; tout passe par inputs, `vars` ou `secrets`.
7. **Ce repo est versionné.** Les projets appellent `@v1`, jamais `@main`.

---

## 2. Branches et flux

Trunk-based : une seule branche durable, `main`. Les branches de travail sont courtes.

```
feature/* ──push / PR──► CI (verify)
     │
     └──label `preview` ou bouton──► build rc ──► image :preview ──► app preprod
     │
     ▼
   main ──push──► verify ─► version ─► publish ─► tag + Release ─► deploy prod
```

| Déclencheur | Job | Résultat |
|---|---|---|
| `pull_request` (ou push hors `main`) | **CI** | lint, tests, build ; image Docker construite sans push |
| PR avec le label `preview`, ou `workflow_dispatch` mode `preview` | **Preview** | version `X.Y.Z-rc.<run>`, image `:preview` + `:pr-<n>`, déploiement sur l'app preprod |
| `push` sur `main` (ou `workflow_dispatch` mode `release`) | **Release** | version `X.Y.Z`, publication (image, package), tag `vX.Y.Z` + GitHub Release, déploiement prod |

- La preprod est **optionnelle par projet** : un projet sans app preprod n'a simplement pas de secret de preview et le job ne tourne pas.
- `main` est sérialisée : `concurrency: release-<repo>` avec `cancel-in-progress: false`. Deux pushes rapprochés donnent deux versions successives.
- La CI d'une branche annule les runs précédents de la même branche (`cancel-in-progress: true`).

---

## 3. Versioning

### Calcul

- La version courante est le **dernier tag** `vX.Y.Z`.
- La version suivante dépend des messages de commit depuis ce tag :

  | Commits | Bump |
  |---|---|
  | rien de particulier | patch |
  | au moins un `feat:` | minor |
  | `feat!:`, `fix!:`… ou `BREAKING CHANGE` | major |

- Le bouton `workflow_dispatch` accepte un input `bump: auto|patch|minor|major` pour forcer.
- **Premier passage (pas encore de tag)** : on part de la version déclarée dans le projet (pom, package.json, Cargo.toml) pour garder la continuité de la numérotation existante.

| Contexte | Version produite |
|---|---|
| Release | `1.4.3` |
| Preview | `1.4.3-rc.<run_number>` |
| CI | `1.4.3-ci.<sha7>` (jamais publiée) |

### Injection

La version est écrite dans le workspace juste avant le build, jamais committée.
Une action unique `set-version` détecte la stack :

| Stack | Fichier dans le repo | Injection |
|---|---|---|
| Maven | `<version>${revision}</version>` + `<revision>0.0.0-SNAPSHOT</revision>` | `-Drevision=1.4.3` ajouté à `.mvn/maven.config` (lu par `mvn` et `mvnw`) ; une version littérale est refusée |
| Node | `"version": "0.0.0"` | `pnpm pkg set version=1.4.3` |
| Rust | `version = "0.0.0"` (package ou workspace) | réécriture de `Cargo.toml` + entrées locales de `Cargo.lock` (`--locked` reste valide) |
| PHP | — | fichier `VERSION` généré à côté de `composer.json` |

### Lecture de la version à l'exécution

Les artefacts produits par la CI contiennent la vraie version :

- **Spring Boot** : goal `build-info` du `spring-boot-maven-plugin` → `BuildProperties.getVersion()`.
- **Node / Nuxt** : `import pkg from './package.json'` ou `define` Vite/Nuxt, lus au build.
- **Rust** : `env!("CARGO_PKG_VERSION")`.
- **Toutes les images** : label OCI `org.opencontainers.image.version` + variable `APP_VERSION`.

En local, la version affichée est le placeholder (`0.0.0-SNAPSHOT`, `0.0.0`).

### Libs Maven

Obligatoire pour une lib publiée : `flatten-maven-plugin` en mode `resolveCiFriendliesOnly`,
sinon le pom publié contient littéralement `${revision}`.

---

## 4. Organisation du repo

```
.github/                              ← ce repo (Rawz06-Studio/.github)
├── ARCHITECTURE.md
├── README.md                         doc d'utilisation (remplace USE.md)
│
├── actions/                          COUCHE 1 — actions composites (steps)
│   ├── setup-java/                   JDK + cache Maven + auth GitHub Packages
│   ├── setup-node/                   pnpm + Node + cache + registre @rawz06-studio
│   ├── setup-php/                    PHP + Composer + cache
│   ├── setup-rust/                   toolchain + targets + cache
│   ├── compute-version/              dernier tag + commits → version
│   ├── set-version/                  injecte la version dans le workspace
│   ├── prepare-image-context/        contexte Docker en artefact
│   ├── resolve-mode/                 événement → release | preview | ci
│   └── dokploy-deploy/               déclenche un déploiement Dokploy
│
├── images/                           IMAGES DE BASE
│   ├── java-runtime/Dockerfile
│   ├── node-runtime/Dockerfile
│   ├── php-runtime/Dockerfile
│   ├── rust-runtime/Dockerfile
│   └── static-web/{Dockerfile,nginx.conf}
│
├── workflow-templates/               MODÈLES pour les projets (Actions → New workflow)
│
└── .github/
    ├── dependabot.yml                github-actions + docker (images/)
    └── workflows/
        ├── _version.yml              COUCHE 2 — jobs réutilisables
        ├── _java.yml
        ├── _node.yml
        ├── _php.yml
        ├── _rust.yml
        ├── _rust-binaries.yml
        ├── _docker.yml
        ├── _deploy.yml
        ├── _release.yml
        │
        ├── java-app.yml              COUCHE 3 — pipelines (un par profil)
        ├── java-lib.yml
        ├── node-app.yml
        ├── php-app.yml
        ├── rust-app.yml
        ├── rust-desktop.yml
        ├── docker-app.yml
        │
        ├── base-images.yml           interne : build des images de base
        ├── self-test.yml             interne : actionlint + fixtures
        └── self-release.yml          interne : tag vX.Y.Z + déplace v1
```

### Couche 1 — actions composites

Uniquement du setup et des briques de steps. Pas de logique de pipeline.

| Action | Rôle | Remplace |
|---|---|---|
| `setup-java` | `actions/setup-java` avec `cache: maven` et `server-id: github` (settings.xml généré proprement, token via env) | 4 heredocs `settings.xml` |
| `setup-node` | pnpm (version lue dans `packageManager`), Node, `cache: pnpm`, `registry-url` + scope | 3 heredocs `.npmrc` + double cache |
| `setup-php` | PHP, extensions, cache Composer | — |
| `setup-rust` | toolchain stable, targets, `Swatinem/rust-cache` | install Rust dupliqué dans 4 repos |
| `compute-version` | sorties `version`, `tag`, `previous_tag`, `bump` | bash de version dupliqué 3× ici + 4 repos Rust |
| `set-version` | écrit la version dans pom / package.json / Cargo.toml | `mvn versions:set`, `npm version`, `bump-version.sh` |
| `dokploy-deploy` | appelle Dokploy avec un token secret, timeout + retry | curl en dur avec l'ID en clair |

### Couche 2 — jobs réutilisables (`_*.yml`)

Un fichier = un job = une responsabilité. Tous acceptent `working-directory`.

| Job | Fait | Sorties |
|---|---|---|
| `_version.yml` | `compute-version` dans le mode demandé | `version`, `tag`, `previous-tag`, `exists` |
| `_java.yml` | `mvn verify` (version injectée) ; option `publish` → `mvn deploy` sur GitHub Packages ; option `image` → jar renommé `app.jar` + `image-files` | artefact de contexte |
| `_node.yml` | scripts `lint typecheck test build` (`--if-present`) ; option `prod-dependencies` (dans `node:<v>-trixie` si `native-modules`) ; `image-files` (`.output` par défaut) | artefact de contexte |
| `_php.yml` | Composer, tests ; pour l'image : `vendor/` sans dev, `VERSION`, projet entier par défaut | artefact de contexte |
| `_rust.yml` | fmt, clippy, test ; pour l'image : binaires musl (`binaries`) dans `bin/`, client WASM (`trunk-dir`) | artefact de contexte |
| `_rust-binaries.yml` | matrice OS/targets (JSON), macOS universel, scripts `scripts/package-*` ou archive par défaut | artefacts `binaries-<plateforme>` |
| `_docker.yml` | extrait le contexte (ou construit depuis le repo), `APP_VERSION` en build-arg, test optionnel (`test-expect`), push et tags selon le mode | image, digest |
| `_release.yml` | tag + GitHub Release (notes générées), assets + `SHA256SUMS`, relance sans doublon | — |
| `_deploy.yml` | environnement GitHub + `dokploy-deploy` ; sans jeton, réussit sans déployer | — |

**Contexte d'image.** Le job de build ne transmet à `_docker` que le Dockerfile et les fichiers listés,
archivés en `.tar` (`prepare-image-context`) : permissions (binaires exécutables) et dossiers cachés
(`.output`) sont conservés, et rien d'autre du repo n'entre dans l'image. Les chemins du Dockerfile
sont relatifs au projet (`COPY app.jar …`, `COPY .output …`, `COPY bin/server …`).

**Actions partagées.** Chaque job récupère les actions de ce repo dans `.rawz06-ci/` à la ref
`tooling-ref` (`v1` par défaut, transmise par les pipelines). `self-test.yml` passe le commit testé :
les jobs sont validés avec les actions de la même version, ce qu'une référence `@v1` en dur empêcherait.

**Permissions.** GitHub vérifie les permissions d'un job réutilisable sans tenir compte de ses `if:`.
`_java` (publication optionnelle) et `_docker` (push optionnel) ne déclarent donc rien et héritent
de l'appelant ; les autres déclarent leur minimum.

### Couche 3 — pipelines

Un pipeline par profil. **Un projet n'a qu'un seul fichier** : le pipeline lit l'événement
et choisit CI, Preview ou Release (`resolve-mode`, dans le job `_version`).

| Pipeline | Profil | Enchaînement |
|---|---|---|
| `java-app.yml` | app Spring Boot | version → `_java` → `_docker` → `_release` → `_deploy` |
| `java-lib.yml` | lib Maven | version → `_java` (publish hors ci) → `_release` |
| `node-app.yml` | Nuxt, serveur Node, front statique buildé | version → `_node` → `_docker` → `_release` → `_deploy` |
| `php-app.yml` | app PHP | version → `_php` → `_docker` → `_release` → `_deploy` |
| `rust-app.yml` | serveur Rust (+ client WASM) | version → `_rust` → `_docker` → `_release` → `_deploy` |
| `rust-desktop.yml` | appli desktop Rust | version → `_rust` (checks) → `_rust-binaries` (hors ci) → `_release` (avec assets) |
| `docker-app.yml` | le Dockerfile fait tout (HTML pur, cas particuliers) | version → `_docker` → `_release` → `_deploy` |

| Mode | Déclencheur | Image | Release | Déploiement |
|---|---|---|---|---|
| `ci` | PR, push hors branche par défaut | construite et testée, non publiée | — | — |
| `preview` | PR avec le label `preview`, ou bouton « preview » | `:<version>-rc.N`, `:preview`, `:pr-N` | — | app preprod (`DOKPLOY_PREVIEW_TOKEN`) |
| `release` | push sur la branche par défaut, ou bouton « release » | `:<version>`, `:latest`, `:sha-…` | tag + GitHub Release | app prod (`DOKPLOY_TOKEN`) |

Un pipeline peut cumuler : RawZLinsoTrackerRust appellera `rust-app.yml` **et** `rust-desktop.yml`
(serveur en image + client desktop en binaires). Les deux calculent la même version ; le second
pipeline, appelé avec `needs:` sur le premier, ajoute ses binaires à la release existante.

**Permissions.** GitHub vérifie aussi les jobs qui seront sautés : un projet accorde donc au pipeline
tout ce que ses jobs déclarent (`contents: write`, `packages: write`), même pour une simple PR.
Chaque job, lui, ne reçoit que son minimum.

**Concurrence.** Elle se règle dans le fichier du projet (modèles ci-dessous) : un seul run à la fois
sur la branche par défaut, pour que deux pushes rapprochés donnent deux versions successives.

#### Côté projet

Les modèles de `workflow-templates/` apparaissent dans *Actions → New workflow* de chaque repo
de l'organisation. Exemple pour une app Java :

```yaml
# .github/workflows/pipeline.yml — le seul fichier du projet
name: Pipeline

on:
  push:
    branches: [main]
  pull_request:
    types: [opened, synchronize, reopened, labeled]
  workflow_dispatch:
    inputs:
      mode:
        type: choice
        default: release
        options: [release, preview]
      bump:
        type: choice
        default: auto
        options: [auto, patch, minor, major]

concurrency:
  group: pipeline-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  pipeline:
    uses: Rawz06-Studio/.github/.github/workflows/java-app.yml@v1
    permissions:
      contents: write
      packages: write
    with:
      image-name: seedgenerator
      dokploy-url: ${{ vars.DOKPLOY_URL }}
    secrets: inherit
```

---

## 5. Images de base

Publiées sur `ghcr.io/rawz06-studio/<image>`, en **packages publics** (pas d'auth pour les tirer).

| Image | Base amont | Contenu |
|---|---|---|
| `java-runtime:25` | `eclipse-temurin:25-jre-noble` | uid 10001, port 8080, `JAVA_OPTS` (`MaxRAMPercentage=75`), `SPRING_PROFILES_ACTIVE=prod`, lance `/app/app.jar` |
| `node-runtime:24` | `node:24-trixie-slim` | uid 1000 (`node`), port 3000, `NODE_ENV=production`, `HOST=0.0.0.0`, tini en PID 1 |
| `php-runtime:8.4` | `dunglas/frankenphp:1-php8.4-trixie` | uid 10001, HTTP sur 8080, racine `/app/public`, intl/opcache/pdo_pgsql/pgsql/zip, `php.ini` de prod |
| `rust-runtime:latest` | `scratch` (+ fichiers de `debian:trixie-slim`) | uid 10001, certificats CA, fuseaux horaires, `/app` et `/tmp` en écriture, aucun shell |
| `static-web:latest` | `nginxinc/nginx-unprivileged:stable-alpine` | uid 101, port 8080, gzip, assets `/assets/` immuables, HTML revalidé, `/healthz`, `NGINX_FALLBACK` pour les SPA |

### Règles

- **Node en Debian, pas en Alpine** : les modules natifs (`better-sqlite3`) compilés dans la CI doivent tourner sur la même libc.
  Les jobs Node qui embarquent des modules natifs tournent dans le conteneur `node:24-trixie` (`container:` du job), même Debian que l'image de runtime.
- **Rust en musl statique** : le binaire ne dépend pas de la glibc du runner (qui passe à Ubuntu 26).
- **Tags** : `java-runtime:25` (mobile, utilisé par les projets) et `java-runtime:25-YYYY.MM.DD` (figé, pour revenir en arrière).
  Pour les images sans version de langage : `latest` et `YYYY.MM.DD`.
- **Fuseau** `Europe/Paris` partout, **uid numérique** partout (`USER 10001:10001`…).
- **Pas de cache de build** : chaque reconstruction repart des paquets à jour.
- **Multi-arch** : `linux/amd64` + `linux/arm64`, chaque architecture construite sur un runner natif (`ubuntu-latest` / `ubuntu-24.04-arm`) puis fusionnées en un manifest. Pas de QEMU.
- **Rebuild** : chaque lundi (cron) et à chaque merge touchant `images/`. Dependabot `docker` propose les montées de tag amont.
- **Tests** : `tests/base-images.sh` vérifie chaque image (utilisateur, fuseau, service HTTP, arrêt propre…) sur les deux architectures avant publication.
- **Liste des images** : `images/images.json` (nom, tag, description).

### Dockerfiles projet types

```dockerfile
# Spring Boot
FROM ghcr.io/rawz06-studio/java-runtime:25
COPY app.jar /app/app.jar
```

```dockerfile
# Nuxt
FROM ghcr.io/rawz06-studio/node-runtime:24
COPY --chown=node:node .output ./.output
CMD ["node", ".output/server/index.mjs"]
```

```dockerfile
# Site statique / SPA
FROM ghcr.io/rawz06-studio/static-web:latest
COPY dist/ /usr/share/nginx/html/
# Seulement pour une SPA :
ENV NGINX_FALLBACK=/index.html
```

Attention à la migration : les apps changent d'utilisateur (uid 10001 ou 1000) et `static-web`
écoute sur **8080** au lieu de 80. Vérifier les volumes montés et le port configuré dans Dokploy.

Les besoins spécifiques restent dans le Dockerfile du projet, par-dessus la base :
Python/uv + plando (RSLFrancoBot, RSLGeneratorAPI), ffmpeg (funradio), Deno (nightbot-admin).

---

## 6. Architectures (amd64 / arm64)

| Quoi | Architectures |
|---|---|
| Images de base | amd64 + arm64 |
| Images des apps (CI) | amd64 uniquement (prod) |
| Binaires desktop Rust | selon la matrice du projet (voir §7) |

**Tester une image en local sur un Mac (arm64)** : l'artefact doit être construit pour Linux arm64.

- Java : `mvn package` puis `docker build` — le jar est portable.
- Nuxt sans module natif : `pnpm build` puis `docker build`.
- Node avec module natif, Rust : build dans le conteneur officiel (`node:24-trixie`, `rust`), puis `docker build`.
  Un script `local-image.sh` fourni par ce repo automatisera ces cas.

---

## 7. Binaires Rust (applis desktop)

Concerne RTerm, Unbing, Plume et le client de RawZLinsoTrackerRust.

`_rust-binaries.yml` :

- **Input `targets`** (JSON) — défaut :

  | Nom | Runner | Target |
  |---|---|---|
  | linux-x86_64 | `ubuntu-22.04` | `x86_64-unknown-linux-gnu` |
  | linux-aarch64 | `ubuntu-22.04-arm` | `aarch64-unknown-linux-gnu` |
  | macos-universal | `macos-latest` | `aarch64-apple-darwin` + `x86_64-apple-darwin` (lipo) |
  | windows-x86_64 | `windows-latest` | `x86_64-pc-windows-msvc` |

  Les binaires desktop Linux restent en glibc (bibliothèques graphiques), construits sur le runner le plus ancien pour rester compatibles.
- **Input `linux_packages`** : bibliothèques système à installer (GPUI, xcb, wayland…).
- **Packaging par défaut** : binaire brut + `.tar.gz` / `.zip` + `SHA256SUMS`.
- **Packaging spécifique** : si le projet fournit `scripts/package-{linux,macos}.sh` ou `scripts/package-windows.ps1`,
  ils sont appelés avec `<target> <version> <dossier de sortie>` (`.app`/`.dmg`, AppImage, installeur Inno Setup…).
- **Vérification optionnelle** : `version_check` exécute le binaire avec `--version` et compare à la version calculée (comme RTerm aujourd'hui).
- Les assets sont attachés à la GitHub Release par `_release.yml`.

Plus tard : actions composites `package-macos-app` et `package-windows-installer` pour le code identique entre Unbing et Plume.

---

## 8. Déploiement (Dokploy) et secrets

- Les jetons de webhook Dokploy actuellement visibles dans les YAML publics **doivent être régénérés**.
- Par projet :

  | Nom | Type | Usage |
  |---|---|---|
  | `DOKPLOY_TOKEN` | secret | jeton du webhook de l'app prod |
  | `DOKPLOY_PREVIEW_TOKEN` | secret | jeton du webhook de l'app preprod (absent = pas de preview) |
  | `DOKPLOY_URL` | variable (org ou repo) | URL de l'instance Dokploy |

  L'action `dokploy-deploy` accepte aussi l'API (`api-key` + `application-id`) à la place du webhook.

- Les apps Dokploy tirent `:latest` (prod) et `:preview` (preprod) ; le déploiement ne fait que déclencher le pull.
- Environnements GitHub `production` et `preview` : historique des déploiements visible dans chaque repo.
- **Permissions explicites** dans chaque job (`contents`, `packages`), jamais héritées par défaut.
- **GitHub Packages entre repos** : un package (ex. `fr.rawz06:audit`) doit autoriser en lecture les repos qui le consomment
  (*Package settings → Manage Actions access*).

---

## 9. Hygiène de ce repo

- **Versions** : tags `v1.2.3` + tag mobile `v1`. Changement cassant → `v2`.
- **Qualité** : `actionlint` + `zizmor` (sécurité des workflows) sur chaque PR.
- **Fixtures** : `tests/fixtures/<profil>/` — un mini-projet par profil, exécuté par `self-test.yml` via les pipelines locaux.
- **Références internes** : un `./actions/x` dans un workflow réutilisable serait résolu dans le repo appelant.
  Les jobs récupèrent donc les actions via `tooling-ref` (voir couche 2). Au passage à `v2`, mettre à jour ce défaut.
- **Dependabot** : un modèle par profil dans le README, à copier dans chaque projet (ce n'est pas centralisable).

---

## 10. Pièges GitHub Actions connus

- Un tag créé avec `GITHUB_TOKEN` ne déclenche aucun autre workflow → la publication se fait dans le même run.
- Un job sauté (`if:` faux) fait sauter ses dépendants → `if: ${{ !failure() && !cancelled() }}` sur les jobs en aval.
- Les inputs d'un workflow réutilisable ne sont que `string`, `number`, `boolean` → les listes passent en JSON (`fromJSON`).
- L'imbrication des workflows réutilisables est limitée en profondeur : trois couches maximum, on n'en ajoute pas.
- `${{ … }}` est substitué avant le shell : jamais d'expression directement dans `run:`, toujours via `env:`.

---

## 11. Migration

Projets pilotes, un par profil :

| Profil | Pilote | Ensuite |
|---|---|---|
| `java-app` | SeedGeneratorAPI | RSLFrancoBot, RSLGeneratorAPI |
| `java-lib` | AuditLib | stubs-generator (cas particulier multi-API) |
| `node-app` (Nuxt) | HyruleMaster | PapyMaster, RawZLinsoTracker, RSL-Website, SeedGeneratorFront |
| `node-app` (serveur) | async-race-getter | geoguessr-map, funradio, clip-papy, async-weekly-seed |
| `docker-app` / statique | error-pages | rawz06.fr |
| `php-app` | nightbot-admin | — |
| `rust-app` + `rust-desktop` | RawZLinsoTrackerRust | — |
| `rust-desktop` | Unbing | Plume, RTerm |

Étapes :

1. Squelette du repo, `actionlint`, `self-release` (premier tag `v1.0.0`).
2. Images de base + `base-images.yml`.
3. Actions composites.
4. Jobs `_*.yml`.
5. Pipelines + fixtures.
6. Pilotes, puis le reste. Les anciens workflows restent en place tant que des projets les appellent, puis sont supprimés.

Harmonisations à faire pendant la migration : Node 24 partout, pnpm via `packageManager` partout (clip-papy passe de npm à pnpm),
`${revision}` dans tous les pom, preprod de RawZLinsoTracker et RSL-Website sortie de la branche `develop`.
