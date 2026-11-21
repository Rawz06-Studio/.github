# Rawz06-Studio / .github

Workflows CI/CD partagés, actions composites et images de base des projets Rawz06-Studio.

> **Refonte en cours.** La cible est décrite dans [ARCHITECTURE.md](ARCHITECTURE.md).
> Les projets non migrés utilisent toujours les anciens workflows documentés dans [USE.md](USE.md).

## Contenu

| Dossier | Rôle |
|---|---|
| [`actions/`](actions) | Actions composites (setup, version, déploiement) |
| [`.github/workflows/`](.github/workflows) | Jobs réutilisables (`_*.yml`) et pipelines par profil |
| [`tests/`](tests) | Tests des scripts du repo |

### Actions disponibles

| Action | Rôle |
|---|---|
| [`compute-version`](actions/compute-version) | Calcule la prochaine version depuis les tags et les Conventional Commits |

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

En CI, `self-test.yml` lance aussi actionlint, zizmor et shellcheck.
