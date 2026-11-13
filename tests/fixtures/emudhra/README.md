These are public CA certificates, not private keys.

`anchors.pem` and `intermediates.pem` were obtained on 2026-11-13 from the incident investigator's datasets:

- https://emudhra.we-have-a-problem.com/roots.json
- https://emudhra.we-have-a-problem.com/impacted-intermediates.json
- Original incident: https://bugzilla.mozilla.org/show_bug.cgi?id=2083449

The four anchors cover both the eMudhra-issued and Sectigo-cross-signed paths. The 16 intermediate certificates contain eight distinct compromised public keys. All certificate and SPKI SHA-256 values were independently checked against the datasets.

`unaffected-root.pem` is ISRG Root X1 from https://letsencrypt.org/certs/isrgrootx1.pem. Its SHA-256 fingerprint is `96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6`.
