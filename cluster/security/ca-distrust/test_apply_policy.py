import copy
import unittest

from apply_policy import make_patch


class PolicyGuardTests(unittest.TestCase):
    def setUp(self):
        self.image = "ghcr.io/ch4n33/kloud-ca-example@sha256:" + "a" * 64
        self.images = {"example": {"output": {"reference": self.image}}}
        self.target = {"name": "different-service", "containers": [{
            "section": "containers", "name": "worker", "source": "vendor/service:1.2", "component": "example"}]}
        self.workload = {"metadata": {"resourceVersion": "73"}, "spec": {"template": {"spec": {
            "imagePullSecrets": [{"name": "custom-registry"}],
            "containers": [{"name": "worker", "image": "vendor/service:1.2"}],
        }}}}

    def test_new_vendor_version_is_never_rolled_back(self):
        self.workload["spec"]["template"]["spec"]["containers"][0]["image"] = "vendor/service:1.3"
        with self.assertRaisesRegex(RuntimeError, "unreviewed image"):
            make_patch(self.workload, self.target, self.images)

    def test_preserves_custom_secret_and_guards_concurrent_change(self):
        before = copy.deepcopy(self.workload)
        patch = make_patch(self.workload, self.target, self.images)
        self.assertEqual(self.workload, before)
        self.assertIn({"op": "test", "path": "/metadata/resourceVersion", "value": "73"}, patch)
        self.assertIn({"op": "add", "path": "/spec/template/spec/imagePullSecrets/-", "value": {"name": "ghcr-ch4n33"}}, patch)
        self.assertTrue(all(p["op"] == "test" or p["path"].endswith("/image") or p["path"].endswith("imagePullSecrets/-") for p in patch))

    def test_current_image_and_secret_need_no_write(self):
        pod = self.workload["spec"]["template"]["spec"]
        pod["containers"][0]["image"] = self.image
        pod["imagePullSecrets"].append({"name": "ghcr-ch4n33"})
        self.assertEqual(make_patch(self.workload, self.target, self.images), [])


if __name__ == "__main__":
    unittest.main()
