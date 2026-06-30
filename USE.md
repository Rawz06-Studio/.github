# Réutilisation des workflows CI/CD

Ce dépôt expose des workflows réutilisables via `workflow_call`.  
Il suffit de les appeler depuis vos projets sans rien copier.

---

## Prérequis

L'authentification se fait via le `GITHUB_TOKEN` généré automatiquement par GitHub Actions. Assurez-vous que le workflow possède les permissions nécessaires (`packages: write` pour la publication, `packages: read` pour la récupération des dépendances internes).

---

## Workflows disponibles

| Workflow | Déclencheur conseillé | Usage |
|---|---|---|
| `maven-ci.yml` | Toutes branches | Build + test Maven |
| `maven-ci-release.yml` | `main` uniquement | Build + test + bump + deploy GitHub Packages |
| `node-ci.yml` | Toutes branches | Install + lint + test + build JS |
| `node-ci-release.yml` | `main` uniquement | + bump version + publish GitHub Packages optionnel |

---

## Cas d'usage

### Application Maven (back, API…)

**CI sur toutes les branches**

`.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches-ignore:
      - main
  pull_request:

jobs:
  ci:
    uses: RawZ06-Studio/.github/.github/workflows/maven-ci.yml@main
```

**Release sur main**

`.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  release:
    uses: RawZ06-Studio/.github/.github/workflows/maven-ci-release.yml@main
    with:
      publishable: true
```

---

### Application Maven avec Java non standard

```yaml
jobs:
  release:
    uses: RawZ06-Studio/.github/.github/workflows/maven-ci-release.yml@main
    with:
      java_version: '17'       # ← changer ici
      publishable: true
```

---

### Application frontend / fullstack JS (pas de publication npm)

**CI sur toutes les branches**

`.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches-ignore:
      - main
  pull_request:

jobs:
  ci:
    uses: RawZ06-Studio/.github/.github/workflows/node-ci.yml@main
```

**Release sur main**

`.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  release:
    uses: RawZ06-Studio/.github/.github/workflows/node-ci-release.yml@main
    with:
      publishable: false       # application, pas de publish npm
```

---

### Librairie JS (publiée sur GitHub Packages)

**CI sur toutes les branches**

`.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches-ignore:
      - main
  pull_request:

jobs:
  ci:
    uses: RawZ06-Studio/.github/.github/workflows/node-ci.yml@main
```

**Release sur main**

`.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  release:
    uses: RawZ06-Studio/.github/.github/workflows/node-ci-release.yml@main
    with:
      publishable: true        # ← lib publiée sur GitHub Packages
```

---

### Projet fullstack (Maven + JS dans le même repo)

`.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches-ignore:
      - main
  pull_request:

jobs:
  ci-back:
    uses: RawZ06-Studio/.github/.github/workflows/maven-ci.yml@main

  ci-front:
    uses: RawZ06-Studio/.github/.github/workflows/node-ci.yml@main
```

`.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    branches:
      - main

jobs:
  release-back:
    uses: RawZ06-Studio/.github/.github/workflows/maven-ci-release.yml@main
    with:
      publishable: true

  release-front:
    needs: release-back          # ← séquencer si nécessaire, sinon supprimer
    uses: RawZ06-Studio/.github/.github/workflows/node-ci-release.yml@main
    with:
      publishable: false
```

---

## Dependabot

Copier ce fichier dans chaque projet pour maintenir les dépendances à jour automatiquement.

`.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: maven      # ← supprimer si projet JS only
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10

  - package-ecosystem: npm        # ← supprimer si projet Maven only
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
```

---

## Référence des inputs

### `maven-ci.yml` / `maven-ci-release.yml`

| Input | Type | Défaut | Description |
|---|---|---|---|
| `java_version` | string | `21` | Version du JDK |

### `node-ci.yml` / `node-ci-release.yml`

| Input | Type | Défaut | Description |
|---|---|---|---|
| `node_version` | string | `22` | Version de Node |
| `publishable` | boolean | `false` | Publier sur GitHub Packages (`release` uniquement) |
