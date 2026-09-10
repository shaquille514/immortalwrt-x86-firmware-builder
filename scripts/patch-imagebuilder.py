#!/usr/bin/env python3
"""Patch the 24.10 ImageBuilder opkg retry without hiding real failures."""

from pathlib import Path
import sys


NEEDLE = "\t$(OPKG) install $(BUILD_PACKAGES)"
REPLACEMENT = (
    "\t$(OPKG) install $(BUILD_PACKAGES) || { rc=$$?; "
    "$(OPKG) configure && $(OPKG) install $(BUILD_PACKAGES) || exit $$rc; }"
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <ImageBuilder Makefile>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    matches = [
        index for index, line in enumerate(lines)
        if line.rstrip("\r\n") == NEEDLE
    ]
    count = len(matches)
    if count != 1:
        print(f"expected exactly one opkg install recipe, found {count}", file=sys.stderr)
        return 1

    index = matches[0]
    newline = "\r\n" if lines[index].endswith("\r\n") else "\n"
    lines[index] = REPLACEMENT + newline
    path.write_text("".join(lines), encoding="utf-8", newline="")
    print(f"patched transient opkg configure retry in {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
