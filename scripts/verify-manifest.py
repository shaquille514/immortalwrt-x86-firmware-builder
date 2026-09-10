#!/usr/bin/env python3
"""Fail when a requested top-level package is absent from a firmware manifest."""

from pathlib import Path
import sys


def manifest_packages(path: Path) -> set[str]:
    packages = set()
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if " - " in line:
            name, _version = line.split(" - ", 1)
        else:
            name = line.split()[0]
        packages.add(name)
    return packages


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <requested-package-list> <firmware-manifest>", file=sys.stderr)
        return 2

    requested = set(Path(sys.argv[1]).read_text(encoding="utf-8").split())
    installed = manifest_packages(Path(sys.argv[2]))
    missing = sorted(requested - installed)
    if missing:
        print("missing requested packages:", ", ".join(missing), file=sys.stderr)
        return 1

    print(f"manifest verified: {len(requested)} requested packages are installed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
