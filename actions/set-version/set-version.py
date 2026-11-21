"""Injecte une version dans les fichiers projet d'un dossier, pour le build uniquement.

Usage : set-version.py <dossier> <version>

  Maven  pom.xml en <version>${revision}</version> : ajoute -Drevision=<v> à
         .mvn/maven.config, que toutes les commandes mvn / mvnw lisent ensuite.
         Une version littérale est refusée (voir ARCHITECTURE.md §3).
  Node   package.json : champ "version".
  Rust   Cargo.toml ([package] ou [workspace.package]) et les entrées locales de
         Cargo.lock, pour que `cargo build --locked` reste valide.
  PHP    composer.json : écrit un fichier VERSION à côté.

Écrit `stacks=<liste>` dans $GITHUB_OUTPUT. Échoue si aucun fichier projet n'est trouvé.
"""

import glob
import json
import os
import re
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
POM_NS = {"m": "http://maven.apache.org/POM/4.0.0"}


class SetVersionError(Exception):
    pass


def set_maven(directory: Path, version: str) -> None:
    root = ET.parse(directory / "pom.xml").getroot()
    declared = (root.findtext("m:version", namespaces=POM_NS) or "").strip()
    if declared != "${revision}":
        raise SetVersionError(
            f"pom.xml déclare <version>{declared or '(absente)'}</version> : "
            "utiliser <version>${revision}</version> avec "
            "<properties><revision>0.0.0-SNAPSHOT</revision></properties>"
        )
    config = directory / ".mvn" / "maven.config"
    config.parent.mkdir(exist_ok=True)
    lines = config.read_text().splitlines() if config.exists() else []
    lines = [line for line in lines if not line.strip().startswith("-Drevision=")]
    lines.append(f"-Drevision={version}")
    config.write_text("\n".join(lines) + "\n")


def set_node(directory: Path, version: str) -> None:
    path = directory / "package.json"
    text = path.read_text()
    data = json.loads(text)
    data["version"] = version
    indent = re.search(r'^([ \t]+)"', text, re.MULTILINE)
    path.write_text(json.dumps(data, indent=indent.group(1) if indent else 2, ensure_ascii=False) + "\n")


def _replace_section_version(text: str, section: str, version: str) -> tuple[str, bool]:
    """Remplace `version = "..."` dans la section TOML donnée, en gardant le reste intact."""
    lines = text.splitlines(keepends=True)
    current = None
    for i, line in enumerate(lines):
        header = re.match(r"^\s*\[\[?\s*([^\[\]]+?)\s*\]\]?\s*(#.*)?$", line)
        if header:
            current = header.group(1)
            continue
        if current == section and re.match(r'^\s*version\s*=\s*"', line):
            lines[i] = re.sub(r'"[^"]*"', f'"{version}"', line, count=1)
            return "".join(lines), True
    return text, False


def _workspace_members(directory: Path, manifest: dict) -> list[Path]:
    members = []
    for pattern in manifest.get("workspace", {}).get("members", []):
        for match in sorted(glob.glob(str(directory / pattern))):
            if (Path(match) / "Cargo.toml").is_file():
                members.append(Path(match) / "Cargo.toml")
    return members


def set_rust(directory: Path, version: str) -> None:
    root_path = directory / "Cargo.toml"
    root_text = root_path.read_text()
    manifest = tomllib.loads(root_text)
    renamed: set[str] = set()

    if isinstance(manifest.get("package", {}).get("version"), str):
        root_text, ok = _replace_section_version(root_text, "package", version)
        if not ok:
            raise SetVersionError("Cargo.toml : version de [package] introuvable")
        renamed.add(manifest["package"]["name"])

    if "version" in manifest.get("workspace", {}).get("package", {}):
        root_text, ok = _replace_section_version(root_text, "workspace.package", version)
        if not ok:
            raise SetVersionError("Cargo.toml : version de [workspace.package] introuvable")
        if manifest.get("package", {}).get("version") == {"workspace": True}:
            renamed.add(manifest["package"]["name"])
        for member in _workspace_members(directory, manifest):
            package = tomllib.loads(member.read_text()).get("package", {})
            if package.get("version") == {"workspace": True}:
                renamed.add(package["name"])

    if not renamed:
        raise SetVersionError("Cargo.toml : aucune version de package à mettre à jour")
    root_path.write_text(root_text)

    lock = directory / "Cargo.lock"
    if lock.exists():
        blocks = lock.read_text().split("\n[[package]]\n")
        for i, block in enumerate(blocks):
            name = re.search(r'^name = "([^"]+)"', block, re.MULTILINE)
            local = not re.search(r"^source = ", block, re.MULTILINE)
            if name and local and name.group(1) in renamed:
                blocks[i] = re.sub(r'^version = "[^"]*"', f'version = "{version}"', block, count=1, flags=re.MULTILINE)
        lock.write_text("\n[[package]]\n".join(blocks))


def set_php(directory: Path, version: str) -> None:
    (directory / "VERSION").write_text(version + "\n")


HANDLERS = (
    ("maven", "pom.xml", set_maven),
    ("node", "package.json", set_node),
    ("rust", "Cargo.toml", set_rust),
    ("php", "composer.json", set_php),
)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage : set-version.py <dossier> <version>", file=sys.stderr)
        return 2
    directory, version = Path(sys.argv[1]), sys.argv[2].removeprefix("v")
    try:
        if not SEMVER.match(version):
            raise SetVersionError(f"version invalide : {version}")
        stacks = []
        for stack, filename, handler in HANDLERS:
            if (directory / filename).is_file():
                handler(directory, version)
                stacks.append(stack)
                print(f"{stack} : {directory / filename} -> {version}")
        if not stacks:
            raise SetVersionError(f"aucun fichier projet dans {directory}")
    except SetVersionError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as f:
            f.write(f"stacks={' '.join(stacks)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
