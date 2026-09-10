#!/usr/bin/env python3
"""生成 opkg 本地源索引 (Packages / Packages.gz)
用法: python3 gen-feed-index.py <ipk目录> [输出目录]
"""
import gzip
import hashlib
import io
import os
import sys
import tarfile

def read_package(ipk):
    control = None
    installed_size = 0
    with tarfile.open(ipk, "r:*") as tf:
        for m in tf.getmembers():
            if m.name.endswith("control.tar.gz"):
                f = tf.extractfile(m)
                with tarfile.open(fileobj=io.BytesIO(f.read()), mode="r:gz") as cf:
                    for cm in cf.getmembers():
                        if cm.name in ("control", "./control"):
                            control = cf.extractfile(cm).read().decode(errors="replace")
            elif m.name.endswith("data.tar.gz"):
                f = tf.extractfile(m)
                with tarfile.open(fileobj=io.BytesIO(f.read()), mode="r:gz") as df:
                    installed_size = sum(dm.size for dm in df.getmembers() if dm.isfile())
        if control is not None:
            return control, installed_size
    raise RuntimeError(f"control not found in {ipk}")


def parse_control(control):
    fields = {}
    current = None
    for line in control.splitlines():
        if line[:1].isspace() and current:
            fields[current] += "\n" + line[1:]
        elif ":" in line:
            key, value = line.split(":", 1)
            current = key.strip()
            fields[current] = value.strip()
    return fields

def main():
    if len(sys.argv) not in (2, 3):
        print(f"用法: {sys.argv[0]} <ipk目录> [输出目录]", file=sys.stderr)
        return 2
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    entries = []
    for fn in sorted(os.listdir(src)):
        if not fn.endswith(".ipk"):
            continue
        path = os.path.join(src, fn)
        with open(path, "rb") as package_file:
            data = package_file.read()
        ctrl, installed_size = read_package(path)
        fields = parse_control(ctrl)
        rec = ["Package: %s" % fields.get("Package", fn.rsplit("_", 2)[0]),
               "Version: %s" % fields.get("Version", "0"),
               "Depends: %s" % fields.get("Depends", ""),
               "Conflicts: %s" % fields.get("Conflicts", ""),
               "Provides: %s" % fields.get("Provides", ""),
               "Section: %s" % fields.get("Section", "base"),
               "Architecture: %s" % fields.get("Architecture", "all"),
               "Installed-Size: %s" % fields.get("Installed-Size", installed_size),
               "Filename: %s" % fn,
               "Size: %d" % len(data),
               "MD5Sum: %s" % hashlib.md5(data).hexdigest(),
               "SHA256sum: %s" % hashlib.sha256(data).hexdigest(),
               "Description: %s" % fields.get("Description", "").replace("\n", "\n "),
               ""]
        entries.append("\n".join(rec))
    index = "\n".join(entries) + "\n"
    os.makedirs(dst, exist_ok=True)
    with open(os.path.join(dst, "Packages"), "w", encoding="utf-8", newline="\n") as f:
        f.write(index)
    with open(os.path.join(dst, "Packages.gz"), "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            compressed.write(index.encode())
    print(f"索引生成: {len(entries)} 包 -> {dst}/Packages(.gz)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
