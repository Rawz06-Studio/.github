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

### Actions disponibles

| Action | Rôle |
|---|---|
| [`compute-version`](actions/compute-version/action.yml) | Calcule la prochaine version depuis les tags et les Conventional Commits |
| [`set-version`](actions/set-version/action.yml) | Injecte la version dans le workspace : `.mvn/maven.config` (pom en `${revision}`), `package.json`, `Cargo.toml` + `Cargo.lock`, `VERSION` (PHP) |
| [`setup-java`](actions/setup-java/action.yml) | JDK (25 par défaut), cache Maven, accès GitHub Packages ; sortie `mvn` (`./mvnw` si présent) |
| [`setup-node`](actions/setup-node/action.yml) | pnpm (`packageManager`), Node (`.nvmrc` ou 24), cache, registre `@rawz06-studio`, `pnpm install --frozen-lockfile` |
| [`setup-php`](actions/setup-php/action.yml) | PHP 8.4 avec les extensions de `php-runtime`, Composer, cache, `composer install` |
| [`setup-rust`](actions/setup-rust/action.yml) | Toolchain (`rust-toolchain.toml` ou stable), targets, composants, musl-tools, cache |
| [`dokploy-deploy`](actions/dokploy-deploy/action.yml) | Déclenche un déploiement Dokploy (webhook ou API), jetons masqués, 3 relances |

Les étapes Maven qui lisent GitHub Packages définissent `MAVEN_USERNAME: ${{ github.actor }}` et
`MAVEN_PASSWORD: ${{ github.token }}` dans leur `env:` : le jeton n'est jamais écrit sur le disque.

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

En CI, `self-test.yml` lance aussi actionlint, zizmor, hadolint, shellcheck et chaque action `setup-*` sur sa fixture ;
`base-images.yml` reconstruit et teste chaque image sur les deux architectures.
