#!/usr/bin/env python3
"""就地修改 .ipk 内 control 的 Depends 行 (opkg 源内修正已停用的依赖名)
用法: python3 patch-ipk-control.py <ipk路径> <旧依赖子串替换对, 如 exfat-mkfs,exfat-fsck:exfatprogs>
"""
import gzip, io, os, shutil, sys, tarfile, tempfile

def rewrite(ipk, old_parts, new_part):
    tmp = ipk + ".tmp"
    with tarfile.open(ipk, "r:*") as src, tarfile.open(tmp, "w:gz") as dst:
        for m in src.getmembers():
            raw = src.extractfile(m).read()
            if m.name.endswith("control.tar.gz"):
                inner = io.BytesIO()
                with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as cf, \
                     tarfile.open(fileobj=inner, mode="w:gz") as co:
                    for cm in cf.getmembers():
                        if not (cm.isfile() or cm.isreg()):
                            ti = tarfile.TarInfo(cm.name)
                            ti.type = cm.type
                            co.addfile(ti)
                            continue
                        data = cf.extractfile(cm).read()
                        if cm.name in ("control", "./control"):
                            text = data.decode(errors="replace")
                            if "Depends:" in text:
                                for o in old_parts:
                                    text = text.replace(o, new_part)
                                print(f"  {ipk.split(chr(92))[-1].split('/')[-1]}: Depends 修正 -> {new_part}")
                                data = text.encode()
                        ti = tarfile.TarInfo(cm.name)
                        ti.size = len(data)
                        co.addfile(ti, io.BytesIO(data))
                raw = inner.getvalue()
            ti = tarfile.TarInfo(m.name)
            ti.size = len(raw)
            dst.addfile(ti, io.BytesIO(raw))
    os.replace(tmp, ipk)

if __name__ == "__main__":
    ipk = sys.argv[1]
    spec = sys.argv[2]
    old, new = spec.split(":")
    old_parts = [o.strip() for o in old.split(",") if o.strip()]
    print(f"patch: {ipk}")
    rewrite(ipk, old_parts, new.strip())
