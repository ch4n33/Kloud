#!/usr/bin/env python3
"""Remove only the two distrusted CA certificates from a PEM bundle."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import ssl


REMOVED_FINGERPRINTS = {
    "86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B",
    "D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4",
}
BEGIN = b"-----BEGIN CERTIFICATE-----"
END = b"-----END CERTIFICATE-----"
CERTIFICATE = re.compile(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\r?\n?", re.DOTALL)


def certificate_fingerprint(pem: bytes) -> str:
    try:
        text = pem.decode("ascii")
        der = ssl.PEM_cert_to_DER_cert(text)
    except (UnicodeDecodeError, ValueError, ssl.SSLError) as exc:
        raise ValueError("invalid PEM certificate in CA bundle") from exc
    return hashlib.sha256(der).hexdigest().upper()


def validate_certificates(certificates: list[bytes]) -> None:
    try:
        text = b"".join(certificates).decode("ascii")
        ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT).load_verify_locations(cadata=text)
    except (UnicodeDecodeError, ValueError, ssl.SSLError) as exc:
        raise ValueError("invalid X.509 certificate in CA bundle") from exc


def filter_bundle(bundle: bytes) -> tuple[bytes, dict[str, int]]:
    matches = list(CERTIFICATE.finditer(bundle))
    if not matches or bundle.count(BEGIN) != len(matches) or bundle.count(END) != len(matches):
        raise ValueError("CA bundle must contain only well-formed CERTIFICATE PEM blocks")
    validate_certificates([match.group(0) for match in matches])

    output: list[bytes] = []
    removed = {fingerprint: 0 for fingerprint in sorted(REMOVED_FINGERPRINTS)}
    offset = 0
    for match in matches:
        output.append(bundle[offset:match.start()])
        pem = match.group(0)
        fingerprint = certificate_fingerprint(pem)
        if fingerprint in REMOVED_FINGERPRINTS:
            removed[fingerprint] += 1
        else:
            output.append(pem)
        offset = match.end()
    output.append(bundle[offset:])

    filtered = b"".join(output)
    remaining = list(CERTIFICATE.finditer(filtered))
    if not remaining or filtered.count(BEGIN) != len(remaining) or filtered.count(END) != len(remaining):
        raise ValueError("filter produced an empty or malformed CA bundle")
    validate_certificates([match.group(0) for match in remaining])
    for match in remaining:
        if certificate_fingerprint(match.group(0)) in REMOVED_FINGERPRINTS:
            raise ValueError("distrusted certificate remains in filtered bundle")
    return filtered, removed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    filtered, removed = filter_bundle(args.source.read_bytes())
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_bytes(filtered)
    print(json.dumps({"removed": removed}, sort_keys=True))


if __name__ == "__main__":
    main()
