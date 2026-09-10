#!/usr/bin/env python3
"""就地修改 .ipk 内 control 的 Depends 行 (opkg 源内修正已停用的依赖名)
用法: python3 patch-ipk-control.py <ipk路径> <旧依赖子串替换对, 如 exfat-mkfs,exfat-fsck:exfatprogs>
"""
import copy
import io
import os
import re
import sys
import tarfile


def replace_depends(text, old_parts, new_part):
    lines = []
    changed = False
    for line in text.splitlines(keepends=True):
        if line.startswith("Depends:"):
            before = line
            for old in old_parts:
                boundary = r"A-Za-z0-9_.+@-"
                line = re.sub(
                    rf"(?<![{boundary}]){re.escape(old)}(?![{boundary}])",
                    new_part,
                    line,
                )
            changed = changed or line != before
        lines.append(line)
    return "".join(lines), changed

def rewrite(ipk, old_parts, new_part):
    tmp = ipk + ".tmp"
    changed_any = False
    with tarfile.open(ipk, "r:*") as src, tarfile.open(tmp, "w:gz") as dst:
        for m in src.getmembers():
            if not m.isfile():
                dst.addfile(copy.copy(m))
                continue
            raw = src.extractfile(m).read()
            if m.name.endswith("control.tar.gz"):
                inner = io.BytesIO()
                with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as cf, \
                     tarfile.open(fileobj=inner, mode="w:gz") as co:
                    for cm in cf.getmembers():
                        if not cm.isfile():
                            co.addfile(copy.copy(cm))
                            continue
                        data = cf.extractfile(cm).read()
                        if cm.name in ("control", "./control"):
                            text = data.decode(errors="replace")
                            text, changed = replace_depends(text, old_parts, new_part)
                            if changed:
                                changed_any = True
                                print(f"  {ipk.split(chr(92))[-1].split('/')[-1]}: Depends 修正 -> {new_part}")
                                data = text.encode()
                        ti = copy.copy(cm)
                        ti.size = len(data)
                        co.addfile(ti, io.BytesIO(data))
                raw = inner.getvalue()
            ti = copy.copy(m)
            ti.size = len(raw)
            dst.addfile(ti, io.BytesIO(raw))
    if not changed_any:
        os.remove(tmp)
        raise RuntimeError("Depends 中未找到待替换的完整包名")
    os.replace(tmp, ipk)

if __name__ == "__main__":
    if len(sys.argv) != 3 or ":" not in sys.argv[2]:
        print(f"用法: {sys.argv[0]} <ipk路径> <旧依赖1,旧依赖2:新依赖>", file=sys.stderr)
        raise SystemExit(2)
    ipk = sys.argv[1]
    spec = sys.argv[2]
    old, new = spec.split(":", 1)
    old_parts = [o.strip() for o in old.split(",") if o.strip()]
    if not old_parts or not new.strip():
        print("旧依赖和新依赖都不能为空", file=sys.stderr)
        raise SystemExit(2)
    print(f"patch: {ipk}")
    try:
        rewrite(ipk, old_parts, new.strip())
    except (OSError, RuntimeError, tarfile.TarError) as error:
        print(f"patch failed: {error}", file=sys.stderr)
        raise SystemExit(1)
