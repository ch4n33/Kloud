import itertools
from pathlib import Path
import unittest

from filter_ca_bundle import REMOVED_FINGERPRINTS, filter_bundle


FIXTURE = Path(__file__).parent / "fixtures" / "ca-bundle.fixture"


def split_certificates(bundle: bytes) -> list[bytes]:
    import re

    return re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\r?\n?", bundle, re.DOTALL)


class FilterCaBundleTests(unittest.TestCase):
    def test_removes_only_the_two_named_roots_and_preserves_other_pem_bytes(self):
        certificates = split_certificates(FIXTURE.read_bytes())
        self.assertEqual(len(certificates), 3)
        for ordering in itertools.permutations(certificates):
            original = b"\n".join(ordering) + b"\n"
            filtered, removed = filter_bundle(original)
            expected = original
            for distrusted in certificates[:2]:
                expected = expected.replace(distrusted, b"", 1)
            self.assertEqual(sum(removed.values()), 2)
            self.assertEqual(set(removed), REMOVED_FINGERPRINTS)
            self.assertEqual(sum(1 for count in removed.values() if count == 1), 2)
            self.assertEqual(filtered, expected)

    def test_absent_target_is_left_unchanged(self):
        unrelated = split_certificates(FIXTURE.read_bytes())[2] + b"\n"
        filtered, removed = filter_bundle(unrelated)
        self.assertEqual(filtered, unrelated)
        self.assertEqual(sum(removed.values()), 0)

    def test_rejects_unmatched_or_malformed_certificate_markers(self):
        for invalid in (b"", b"-----BEGIN CERTIFICATE-----\nnot a cert\n", b"-----END CERTIFICATE-----\n"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    filter_bundle(invalid)


if __name__ == "__main__":
    unittest.main()
