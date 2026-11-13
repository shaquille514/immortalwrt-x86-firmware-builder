#!/usr/bin/env python3
"""Install a fail-closed CA-store check between rootfs preparation and imaging."""

from pathlib import Path
import sys


ANCHOR = "\t$(MAKE) -s prepare_rootfs\n\t$(MAKE) -s build_image\n"
HOOK = ('\tpython3 "$(GITHUB_WORKSPACE)/scripts/harden-ca-store.py" "$(TARGET_DIR)" '
        '--policy "$(GITHUB_WORKSPACE)/security/emudhra-denylist.json" '
        '--report "$(BIN_DIR)/emudhra-ca-audit.json"\n')


def patch(path):
    source = path.read_text(encoding="utf-8")
    if "harden-ca-store.py" in source or source.count(ANCHOR) != 1:
        raise ValueError("ImageBuilder CA hook anchor changed or was already patched")
    source = source.replace(ANCHOR, "\t$(MAKE) -s prepare_rootfs\n" + HOOK + "\t$(MAKE) -s build_image\n")
    path.write_text(source, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    try:
        patch(Path(sys.argv[1]))
    except (IndexError, OSError, ValueError) as error:
        print(f"ImageBuilder CA hook failed: {error}", file=sys.stderr)
        sys.exit(1)
