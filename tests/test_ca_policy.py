"""Regression tests using the incident's public certificates; no network access."""

import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "tests/fixtures/emudhra"
POLICY = REPO / "security/emudhra-denylist.json"


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / filename)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


guard = module("ca_guard", "harden-ca-store.py")
hook = module("ca_hook", "patch-imagebuilder-ca.py")


class CAPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "rootfs"
        self.store = self.root / "etc/ssl/certs"
        self.store.mkdir(parents=True)
        self.anchors = (FIXTURES / "anchors.pem").read_bytes()
        self.intermediates = (FIXTURES / "intermediates.pem").read_bytes()
        self.safe = (FIXTURES / "unaffected-root.pem").read_bytes()
        self.policy, self.blocked = guard.load_policy(POLICY)
        self.bundle = self.store / "ca-certificates.crt"
        self.bundle.write_bytes(self.anchors + self.intermediates + self.safe)

    def test_public_fixtures_match_pinned_incident_inventory(self):
        actual = {}
        for match in guard.PEM.finditer(self.intermediates):
            fingerprint, spki = guard.certificate_hashes(match[0])
            actual.setdefault(spki, set()).add(fingerprint)
        expected = {item["spki_sha256"]: set(item["certificate_sha256"])
                    for item in self.policy["compromised_keys"]}
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 8)
        self.assertTrue(all(len(certificates) == 2 for certificates in actual.values()))
        self.assertEqual(guard.certificate_hashes(self.safe)[0],
                         "96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6")

    def test_bundle_individual_files_and_hash_links_are_filtered(self):
        unsafe = self.store / "renamed-anchor.crt"
        unsafe.write_bytes(next(guard.PEM.finditer(self.anchors))[0])
        safe_file = self.store / "unaffected.crt"
        safe_file.write_bytes(self.safe)
        link = self.store / "01234567.0"
        symlinks_supported = True
        try:
            link.symlink_to(unsafe.name)
        except OSError:
            symlinks_supported = False
        report = guard.harden(self.root, self.policy, self.blocked, POLICY)
        self.assertEqual(len(list(guard.PEM.finditer(self.bundle.read_bytes()))), 1)
        self.assertIn(self.safe.strip(), self.bundle.read_bytes())
        self.assertFalse(unsafe.exists())
        self.assertEqual(safe_file.read_bytes(), self.safe)
        if symlinks_supported:
            self.assertFalse(link.is_symlink())
        self.assertEqual(len(report["removed"]), 21)
        self.assertTrue((self.root / "usr/share/ca-policy/emudhra.json").is_file())
        # A second pass must preserve the safe store and report no further removals.
        before = self.bundle.read_bytes()
        self.assertEqual(guard.harden(self.root, self.policy, self.blocked, POLICY)["removed"], [])
        self.assertEqual(self.bundle.read_bytes(), before)

    def test_missing_or_empty_bundle_fails_without_mutation(self):
        self.bundle.write_bytes(self.anchors)
        before = self.bundle.read_bytes()
        with self.assertRaisesRegex(ValueError, "empty"):
            guard.harden(self.root, self.policy, self.blocked, POLICY)
        self.assertEqual(self.bundle.read_bytes(), before)
        self.bundle.unlink()
        with self.assertRaisesRegex(ValueError, "no populated"):
            guard.harden(self.root, self.policy, self.blocked, POLICY)

    def test_malformed_certificate_fails_before_any_mutation(self):
        before = self.bundle.read_bytes()
        (self.store / "zzz-malformed.crt").write_bytes(b"-----BEGIN CERTIFICATE-----\nbroken")
        with self.assertRaises(ValueError):
            guard.harden(self.root, self.policy, self.blocked, POLICY)
        self.assertEqual(self.bundle.read_bytes(), before)

    def test_unexpected_trusted_pem_format_is_not_silently_accepted(self):
        (self.store / "trusted.pem").write_bytes(b"-----BEGIN TRUSTED CERTIFICATE-----\nAA==\n-----END TRUSTED CERTIFICATE-----")
        with self.assertRaisesRegex(ValueError, "unsupported"):
            guard.harden(self.root, self.policy, self.blocked, POLICY)

    def test_tar_audit_rejects_unsafe_and_accepts_hardened_rootfs(self):
        archive = self.root.parent / "rootfs.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            output.add(self.root / "etc", arcname="./etc")
        with self.assertRaisesRegex(ValueError, "blocked trust path"):
            guard.inspect_archive(archive, self.blocked)
        guard.harden(self.root, self.policy, self.blocked, POLICY)
        with tarfile.open(archive, "w:gz") as output:
            output.add(self.root / "etc", arcname="./etc")
        self.assertEqual(guard.inspect_archive(archive, self.blocked)["certificates_checked"], 1)

    @unittest.skipUnless(shutil.which("openssl"), "OpenSSL CLI required for independent chain verification")
    def test_direct_and_cross_signed_chains_are_rejected_but_safe_root_survives(self):
        self.bundle.write_bytes(self.anchors + self.safe)
        before = self.root.parent / "before.pem"
        before.write_bytes(self.bundle.read_bytes())
        guard.harden(self.root, self.policy, self.blocked, POLICY)
        for index, match in enumerate(guard.PEM.finditer(self.intermediates)):
            certificate = self.root.parent / f"intermediate-{index}.pem"
            certificate.write_bytes(match[0])
            command = ["openssl", "verify", "-no-CApath", "-no-CAstore", "-purpose", "any", "-CAfile"]
            original = subprocess.run(command + [str(before), str(certificate)], capture_output=True)
            self.assertEqual(original.returncode, 0, original.stderr.decode())
            hardened = subprocess.run(command + [str(self.bundle), str(certificate)], capture_output=True)
            self.assertNotEqual(hardened.returncode, 0, f"accepted incident chain {index}")
        safe_file = self.root.parent / "safe.pem"
        safe_file.write_bytes(self.safe)
        result = subprocess.run(["openssl", "verify", "-CAfile", str(self.bundle), str(safe_file)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        # Independently compare the DER SPKI parser with OpenSSL's serialization.
        public_key = subprocess.run(["openssl", "x509", "-in", str(before), "-pubkey", "-noout"],
                                    capture_output=True, check=True).stdout
        spki = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=public_key,
                              capture_output=True, check=True).stdout
        self.assertEqual(hashlib.sha256(spki).hexdigest().upper(),
                         guard.certificate_hashes(next(guard.PEM.finditer(self.anchors))[0])[1])

    def test_hook_requires_unique_unmodified_anchor(self):
        path = self.root.parent / "Makefile"
        path.write_text("_call_image:\n" + hook.ANCHOR)
        hook.patch(path)
        self.assertIn(hook.HOOK, path.read_text())
        with self.assertRaises(ValueError):
            hook.patch(path)
        path.write_text("_call_image:\n\t$(MAKE) -s build_image\n")
        with self.assertRaises(ValueError):
            hook.patch(path)

    @unittest.skipUnless(shutil.which("make") and os.name != "nt", "GNU make required")
    def test_hook_runs_after_preparation_and_stops_imaging_on_failure(self):
        path = self.root.parent / "Makefile"
        output = self.root.parent / "out"
        output.mkdir()
        source = (f"TARGET_DIR := {self.root}\nBIN_DIR := {output}\nGITHUB_WORKSPACE := {REPO}\n"
                  "_call_image:\n" + hook.ANCHOR +
                  f"prepare_rootfs:\n\tcat '{FIXTURES / 'anchors.pem'}' '{FIXTURES / 'unaffected-root.pem'}' > '$(TARGET_DIR)/etc/ssl/certs/ca-certificates.crt'\n"
                  "build_image:\n\ttouch '$(BIN_DIR)/image-built'\n")
        path.write_text(source)
        hook.patch(path)
        success = subprocess.run(["make", "-f", str(path), "_call_image"], cwd=path.parent, capture_output=True)
        self.assertEqual(success.returncode, 0, success.stderr.decode())
        self.assertTrue((output / "image-built").exists())
        self.assertEqual(len(json.loads((output / "emudhra-ca-audit.json").read_text())["removed"]), 4)
        (output / "image-built").unlink()
        source = source.replace(f"cat '{FIXTURES / 'anchors.pem'}' '{FIXTURES / 'unaffected-root.pem'}'", "printf ''")
        path.write_text(source)
        hook.patch(path)
        failure = subprocess.run(["make", "-f", str(path), "_call_image"], cwd=path.parent, capture_output=True)
        self.assertNotEqual(failure.returncode, 0)
        self.assertFalse((output / "image-built").exists())


if __name__ == "__main__":
    unittest.main()
