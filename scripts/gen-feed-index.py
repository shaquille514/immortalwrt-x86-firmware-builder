#!/usr/bin/env python3
"""生成 opkg 本地源索引 (Packages / Packages.gz)
用法: python3 gen-feed-index.py <ipk目录> [输出目录]
"""
import gzip, hashlib, io, os, sys, tarfile

def read_control(ipk):
    with tarfile.open(ipk, "r:*") as tf:
        for m in tf.getmembers():
            if m.name.endswith("control.tar.gz"):
                f = tf.extractfile(m)
                with tarfile.open(fileobj=io.BytesIO(f.read()), mode="r:gz") as cf:
                    for cm in cf.getmembers():
                        if cm.name in ("control", "./control"):
                            return cf.extractfile(cm).read().decode(errors="replace")
                break
    raise RuntimeError(f"control not found in {ipk}")

def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    entries = []
    for fn in sorted(os.listdir(src)):
        if not fn.endswith(".ipk"):
            continue
        path = os.path.join(src, fn)
        data = open(path, "rb").read()
        ctrl = read_control(path)
        fields = {}
        for line in ctrl.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fields[k.strip()] = v.strip()
        rec = ["Package: %s" % fields.get("Package", fn.rsplit("_", 2)[0]),
               "Version: %s" % fields.get("Version", "0"),
               "Depends: %s" % fields.get("Depends", ""),
               "Conflicts: %s" % fields.get("Conflicts", ""),
               "Provides: %s" % fields.get("Provides", ""),
               "Section: %s" % fields.get("Section", "base"),
               "Architecture: %s" % fields.get("Architecture", "all"),
               "Installed-Size: %d" % (len(data) // 1024),
               "Filename: %s" % fn,
               "Size: %d" % len(data),
               "MD5Sum: %s" % hashlib.md5(data).hexdigest(),
               "SHA256sum: %s" % hashlib.sha256(data).hexdigest(),
               "Description: %s" % fields.get("Description", "").replace("\n", " "),
               ""]
        entries.append("\n".join(rec))
    index = "\n".join(entries) + "\n"
    os.makedirs(dst, exist_ok=True)
    with open(os.path.join(dst, "Packages"), "w") as f:
        f.write(index)
    with gzip.open(os.path.join(dst, "Packages.gz"), "wb") as f:
        f.write(index.encode())
    print(f"索引生成: {len(entries)} 包 -> {dst}/Packages(.gz)")

if __name__ == "__main__":
    main()
