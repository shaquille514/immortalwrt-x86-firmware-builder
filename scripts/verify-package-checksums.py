#!/usr/bin/env python3
"""Verify that SHA256SUMS covers exactly every bundled IPK and APK."""

import hashlib
from pathlib import Path
import sys


ALLOWED_ROOTS = (Path("packages/local"), Path("packages/apk25"))


def bundled_packages(repo_root: Path) -> set[Path]:
    files: set[Path] = set()
    for root in ALLOWED_ROOTS:
        package_root = repo_root / root
        files.update(path.relative_to(repo_root) for path in package_root.glob("*.ipk"))
        files.update(path.relative_to(repo_root) for path in package_root.glob("*.apk"))
    return files


def parse_checksum_file(path: Path) -> dict[Path, str]:
    entries: dict[Path, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line:
            continue
        try:
            digest, raw_name = line.split(maxsplit=1)
        except ValueError as error:
            raise ValueError(f"line {line_number}: malformed checksum") from error
        name = raw_name.removeprefix("*")
        package = Path(name)
        if len(digest) != 64 or any(char not in "0123456789abcdefABCDEF" for char in digest):
            raise ValueError(f"line {line_number}: invalid SHA256")
        if package.is_absolute() or ".." in package.parts:
            raise ValueError(f"line {line_number}: unsafe path: {name}")
        if package in entries:
            raise ValueError(f"line {line_number}: duplicate path: {name}")
        entries[package] = digest.lower()
    return entries


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <SHA256SUMS>", file=sys.stderr)
        return 2

    try:
        checksum_path = Path(sys.argv[1]).resolve()
        entries = parse_checksum_file(checksum_path)
    except (OSError, ValueError) as error:
        print(f"checksum manifest error: {error}", file=sys.stderr)
        return 1

    repo_root = checksum_path.parent.parent
    actual = bundled_packages(repo_root)
    listed = set(entries)
    missing = sorted(actual - listed)
    extra = sorted(listed - actual)
    if missing:
        print("unlisted bundled packages:", *(str(path) for path in missing), file=sys.stderr)
    if extra:
        print("missing files listed in checksum manifest:", *(str(path) for path in extra), file=sys.stderr)
    if missing or extra:
        return 1

    failed = []
    for package, expected in sorted(entries.items()):
        actual_digest = hashlib.sha256((repo_root / package).read_bytes()).hexdigest()
        if actual_digest != expected:
            failed.append(package)
    if failed:
        print("checksum mismatch:", *(str(path) for path in failed), file=sys.stderr)
        return 1

    print(f"verified {len(entries)} bundled package checksums")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
