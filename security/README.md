# eMudhra CA incident policy

The 2026-10-17 incident compromised eight intermediate CA keys. Removing only the intermediate PEM files is insufficient: a server can supply those certificates, and Sectigo cross-certificates offer another path to a trusted root. Debian's security fix removes both `emSign ECC Root CA - G3` and `AAA Certificate Services`:

- https://bugs.debian.org/1151413
- https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
- https://blog.mozilla.org/security/2026/10/20/protecting-firefox-users-following-the-compromise-of-emudhra-intermediate-certificates/

`emudhra-denylist.json` pins the eight compromised public keys and four known path anchors by SHA-256 of SubjectPublicKeyInfo. The two additional anchors, `emSign Root TLS CA - G3` and `emSign Root CS CA - G3`, are relevant to other trust-store distributions and are removed if present. This does not assert that the anchor private keys were compromised. Certificates that reuse these keys, including cross-signed variants, match the policy.

The firmware workflow filters the installed system CA bundle and individual CA files **after** package installation and rootfs preparation, **before** generating images. A changed ImageBuilder hook, missing/empty CA bundle, or malformed certificate fails the build. The emitted rootfs tar archives are then checked independently. The Release includes `emudhra-ca-audit.json`; the installed image also contains `/usr/share/ca-policy/emudhra.json`.

This mitigation affects every certificate chain relying solely on these anchors, including otherwise legitimate sites using the old AAA chain. It preserves unrelated roots and does not disable TLS verification. Private application stores, explicitly configured proxy certificates, containers, Java stores, and browser stores need separate updates. Go applications with embedded/custom roots should be rebuilt with the CVE-2026-111943 fix (Go 1.26.10 / 1.27.3 or a patched successor). Later upgrading `ca-bundle` or `ca-certificates` can replace the filtered files; use an upstream-fixed package or rebuild a checked image before doing so.

This is a pinned incident mitigation, not a general automatic revocation service. Review new incident data and policy changes explicitly. The ImageBuilder versions and repository-local IPK/APK snapshots remain pinned; rebuilding does not automatically upgrade them.
