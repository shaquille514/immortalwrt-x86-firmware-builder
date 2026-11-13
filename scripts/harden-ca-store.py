#!/usr/bin/env python3
"""Remove eMudhra incident trust paths from a staged OpenWrt filesystem."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tarfile
import tempfile


REPO = Path(__file__).resolve().parent.parent
PEM = re.compile(rb"-----BEGIN CERTIFICATE-----\s+([A-Za-z0-9+/=\s]+?)-----END CERTIFICATE-----")
TRUST_DIRS = ("etc/ssl/certs", "usr/share/ca-certificates", "usr/local/share/ca-certificates")


def tlv(data, offset):
    """Read one definite-length DER element, including its bounds."""
    start = offset
    if offset + 2 > len(data):
        raise ValueError("truncated DER element")
    tag, length = data[offset:offset + 2]
    offset += 2
    if length & 128:
        count = length & 127
        if not 1 <= count <= 4 or offset + count > len(data):
            raise ValueError("invalid DER length")
        length = int.from_bytes(data[offset:offset + count], "big")
        offset += count
    end = offset + length
    if end > len(data):
        raise ValueError("DER length exceeds input")
    return tag, start, offset, end


def certificate_hashes(pem):
    match = PEM.fullmatch(pem.strip())
    if not match:
        raise ValueError("invalid certificate PEM")
    der = base64.b64decode(re.sub(rb"\s", b"", match[1]), validate=True)
    outer = tlv(der, 0)
    if outer[0] != 48 or outer[3] != len(der):
        raise ValueError("invalid X.509 certificate sequence")
    tbs = tlv(der, outer[2])
    if tbs[0] != 48 or tbs[3] > outer[3]:
        raise ValueError("invalid TBSCertificate")
    pos = tbs[2]
    if der[pos] == 160:  # optional explicit version
        pos = tlv(der, pos)[3]
    for expected in (2, 48, 48, 48, 48):  # serial, signature, issuer, validity, subject
        item = tlv(der, pos)
        if item[0] != expected or item[3] > tbs[3]:
            raise ValueError("invalid TBSCertificate field")
        pos = item[3]
    spki = tlv(der, pos)
    if spki[0] != 48 or spki[3] > tbs[3]:
        raise ValueError("invalid SubjectPublicKeyInfo")
    return (hashlib.sha256(der).hexdigest().upper(),
            hashlib.sha256(der[spki[1]:spki[3]]).hexdigest().upper())


def load_policy(path):
    policy = json.loads(path.read_text(encoding="utf-8"))
    entries = policy["trust_anchors"] + policy["compromised_keys"]
    hashes = {}
    for entry in entries:
        digest = entry["spki_sha256"]
        if not re.fullmatch(r"[0-9A-F]{64}", digest):
            raise ValueError("invalid policy SPKI fingerprint")
        if digest in hashes:
            raise ValueError("duplicate policy SPKI fingerprint")
        hashes[digest] = entry["name"]
    if len(policy["compromised_keys"]) != 8 or len(policy["trust_anchors"]) != 4:
        raise ValueError("incomplete eMudhra incident policy")
    return policy, hashes


def filter_pem(data, blocked):
    if b"-----BEGIN TRUSTED CERTIFICATE-----" in data:
        raise ValueError("unsupported OpenSSL TRUSTED CERTIFICATE format")
    matches = list(PEM.finditer(data))
    if (not matches or data.count(b"-----BEGIN CERTIFICATE-----") != len(matches)
            or data.count(b"-----END CERTIFICATE-----") != len(matches)):
        raise ValueError("missing or malformed certificate PEM")
    removed, kept = [], 0

    def replace(match):
        nonlocal kept
        fingerprint, spki = certificate_hashes(match[0])
        if spki in blocked:
            removed.append({"sha256": fingerprint, "spki_sha256": spki, "name": blocked[spki]})
            return b""
        kept += 1
        return match[0]

    result = PEM.sub(replace, data)
    return result, removed, kept


def trust_path(name):
    name = name.removeprefix("./")
    return name == "etc/ssl/cert.pem" or any(name.startswith(folder + "/") for folder in TRUST_DIRS)


def inspect_archive(path, blocked):
    bundles, certificates = 0, 0
    with tarfile.open(path, "r:*") as archive:
        for member in archive:
            if not member.isfile() or not trust_path(member.name):
                continue
            data = archive.extractfile(member).read()
            if b"-----BEGIN TRUSTED CERTIFICATE-----" in data:
                raise ValueError(f"unsupported trusted-certificate format: {member.name}")
            if b"-----BEGIN CERTIFICATE" not in data:
                if data.strip() and Path(member.name).suffix.lower() in (".crt", ".pem"):
                    raise ValueError(f"unsupported CA certificate encoding: {member.name}")
                continue
            _, removed, kept = filter_pem(data, blocked)
            if removed:
                raise ValueError(f"blocked trust path remains in {path.name}:{member.name}")
            certificates += kept
            if member.name.removeprefix("./") == "etc/ssl/certs/ca-certificates.crt":
                bundles += 1
    if not bundles or not certificates:
        raise ValueError(f"no populated system CA bundle found in {path}")
    return {"archive": path.name, "certificates_checked": certificates}


def atomic_write(path, data):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        output.write(data)
    try:
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def harden(root, policy, blocked, policy_path):
    root = root.resolve()
    if root == Path(root.anchor) or not (root / "etc/ssl/certs").is_dir():
        raise ValueError("expected a staged rootfs containing etc/ssl/certs")
    changes, removed_paths, findings = [], set(), []
    candidates = set()
    for folder in TRUST_DIRS:
        directory = root / folder
        if directory.is_symlink():
            raise ValueError(f"trust directory must not be a symlink: {folder}")
        if directory.exists():
            candidates.update(directory.rglob("*"))
    candidates.add(root / "etc/ssl/cert.pem")
    bundle_seen = False
    for path in sorted(candidates):
        if path.is_symlink() or not path.exists() or not stat.S_ISREG(path.stat().st_mode):
            continue
        if not path.resolve().is_relative_to(root):
            raise ValueError("trust-store file escapes staged rootfs")
        data = path.read_bytes()
        if b"-----BEGIN TRUSTED CERTIFICATE-----" in data:
            raise ValueError(f"unsupported trusted-certificate format: {path}")
        if b"-----BEGIN CERTIFICATE" not in data:
            if data.strip() and path.suffix.lower() in (".crt", ".pem"):
                raise ValueError(f"unsupported CA certificate encoding: {path}")
            continue
        filtered, removed, kept = filter_pem(data, blocked)
        relative = path.relative_to(root).as_posix()
        if relative == "etc/ssl/certs/ca-certificates.crt":
            if not kept:
                raise ValueError("refusing to create an empty system CA bundle")
            bundle_seen = True
        if removed:
            findings.extend(dict(item, file=relative) for item in removed)
            if kept:
                changes.append((path, filtered))
            else:
                removed_paths.add(path)
    if not bundle_seen:
        raise ValueError("no populated system CA bundle found")
    # Validate the entire store before changing any certificate file.
    for path, data in changes:
        atomic_write(path, data)
    for path in removed_paths:
        path.unlink()
    for path in sorted(candidates):
        if not path.is_symlink():
            continue
        target = os.readlink(path)
        target_path = root / target.lstrip("/") if target.startswith("/") else path.parent / target
        if Path(os.path.abspath(target_path)) in removed_paths:
            path.unlink()
    audit = {"policy": policy["id"], "policy_sha256": hashlib.sha256(policy_path.read_bytes()).hexdigest(),
             "removed": findings, "scope": "system CA stores; not application-private trust stores"}
    destination = root / "usr/share/ca-policy"
    if destination.is_symlink() or not destination.resolve().is_relative_to(root):
        raise ValueError("policy report directory escapes staged rootfs")
    destination.mkdir(parents=True, exist_ok=True)
    atomic_write(destination / "emudhra.json", (json.dumps(audit, indent=2, ensure_ascii=False) + "\n").encode())
    return audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rootfs", nargs="?", type=Path)
    parser.add_argument("--policy", type=Path, default=REPO / "security/emudhra-denylist.json")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--check-tar", type=Path)
    args = parser.parse_args()
    try:
        policy, blocked = load_policy(args.policy)
        if args.check_tar:
            audit = inspect_archive(args.check_tar, blocked)
        else:
            if args.rootfs is None:
                parser.error("rootfs or --check-tar is required")
            audit = harden(args.rootfs, policy, blocked, args.policy)
        if args.report:
            atomic_write(args.report, (json.dumps(audit, indent=2, ensure_ascii=False) + "\n").encode())
        print(json.dumps(audit, ensure_ascii=False))
    except (ValueError, OSError, KeyError, IndexError, tarfile.TarError) as error:
        print(f"CA policy failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
