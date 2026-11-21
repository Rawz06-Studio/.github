"""Affiche la version déclarée par le projet (pom.xml, package.json, Cargo.toml).

Utilisé uniquement pour la toute première release, quand aucun tag n'existe.
N'affiche rien si aucune version n'est trouvée.
"""

import json
import re
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path


def from_pom(path: Path) -> str | None:
    ns = {"m": "http://maven.apache.org/POM/4.0.0"}
    root = ET.parse(path).getroot()
    version = root.findtext("m:version", namespaces=ns)
    if version is None:
        return None
    # CI-friendly : <version>${revision}</version> + <properties><revision>...</revision>
    def resolve(match: re.Match) -> str:
        value = root.findtext(f"m:properties/m:{match.group(1)}", namespaces=ns)
        return value or ""

    return re.sub(r"\$\{([^}]+)\}", resolve, version).strip() or None


def from_package_json(path: Path) -> str | None:
    return json.loads(path.read_text()).get("version")


def from_cargo(path: Path) -> str | None:
    data = tomllib.loads(path.read_text())
    version = data.get("package", {}).get("version")
    if isinstance(version, str):
        return version
    return data.get("workspace", {}).get("package", {}).get("version")


READERS = (
    ("pom.xml", from_pom),
    ("package.json", from_package_json),
    ("Cargo.toml", from_cargo),
)


def main() -> None:
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    for name, reader in READERS:
        path = directory / name
        if path.is_file():
            version = reader(path)
            if version:
                print(version)
            return


if __name__ == "__main__":
    main()
