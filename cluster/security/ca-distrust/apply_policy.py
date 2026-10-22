#!/usr/bin/env python3
"""검사한 공용 이미지에만 CA 불신 정책을 적용한다. 기본 동작은 읽기 전용이다."""
import argparse
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTEXT = "kloud"
PULL_SECRET = "ghcr-ch4n33"
NAMESPACES = {"cert-manager", "metallb-system", "kube-system", "kloud-metrics", "kloud-vpn"}
APP_EXCEPTION = {"blog", "character-sites", "minio", "obsidian-couchdb", "sample-app", "minecraft"}


def require(condition, message="CA policy validation failed"):
    if not condition:
        raise RuntimeError(message)


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def kube(*args):
    return command("kubectl", "--kubeconfig", str(Path.home() / ".kube/config"), "--context", CONTEXT, *args)


def verify_environment():
    require(command("git", "-C", str(ROOT), "rev-parse", "--show-toplevel") == str(ROOT))
    require(command("git", "-C", str(ROOT), "remote", "get-url", "origin") == "https://github.com/ch4n33/Kloud.git")
    common = command("git", "-C", str(ROOT), "rev-parse", "--git-common-dir")
    require((ROOT / common).resolve() == ROOT / ".git", "canonical Kloud checkout required")
    server = kube("config", "view", "--minify", "-o", "jsonpath={.clusters[0].cluster.server}")
    require(server == "https://k3s.kloud.rche.moe:6443", server)
    nodes = json.loads(kube("get", "nodes", "-o", "json"))["items"]
    nas = next(n for n in nodes if n["metadata"]["name"] == "ch4n33-server")
    require(any(a["type"] == "InternalIP" and a["address"] == "192.168.50.18" for a in nas["status"]["addresses"]))
    require(any(c["type"] == "Ready" and c["status"] == "True" for c in nas["status"]["conditions"]))


def make_patch(workload, target, images):
    """동시 변경과 검사하지 않은 버전을 거부하며 다른 설정은 보존한다."""
    pod = workload["spec"]["template"]["spec"]
    patch = [{"op": "test", "path": "/metadata/resourceVersion", "value": workload["metadata"]["resourceVersion"]}]
    for item in target["containers"]:
        replacement = images[item["component"]]["output"]["reference"]
        require(replacement.startswith("ghcr.io/ch4n33/") and "@sha256:" in replacement)
        section = item["section"]
        idx, container = next((i, c) for i, c in enumerate(pod[section]) if c["name"] == item["name"])
        current = container["image"]
        if current == replacement:
            continue
        require(current == item["source"], f"unreviewed image: {target['name']}/{item['name']}: {current}")
        path = f"/spec/template/spec/{section}/{idx}/image"
        patch.extend([{"op": "test", "path": path, "value": current}, {"op": "replace", "path": path, "value": replacement}])
    if not any(s["name"] == PULL_SECRET for s in pod.get("imagePullSecrets", [])):
        path = "/spec/template/spec/imagePullSecrets"
        if "imagePullSecrets" in pod:
            patch.append({"op": "add", "path": path + "/-", "value": {"name": PULL_SECRET}})
        else:
            patch.append({"op": "add", "path": path, "value": [{"name": PULL_SECRET}]})
    return patch if len(patch) > 1 else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", help="namespace/name: 한 워크로드씩 선택")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply and not args.target:
        parser.error("--apply requires --target; roll out one workload at a time")
    verify_environment()
    images = {}
    for filename in ["image-lock.json", "legacy-image-lock.json", "minecraft/image-lock.json"]:
        path = HERE / filename
        if not path.exists():
            continue
        lock = json.loads(path.read_text())
        require(lock["schemaVersion"] == 1)
        for image in lock["images"]:
            require(image["name"] not in images, "duplicate component in CA locks")
            images[image["name"]] = image
    targets = json.loads((HERE / "targets.json").read_text())["targets"]
    if args.target:
        targets = [t for t in targets if f"{t['namespace']}/{t['name']}" == args.target]
        require(len(targets) == 1, "unknown target")
    for target in targets:
        ns = target["namespace"]
        require(ns in NAMESPACES or (ns == "kloud-apps" and target["name"] in APP_EXCEPTION))
        workload = json.loads(kube("-n", ns, "get", target["kind"], target["name"], "-o", "json"))
        patch = make_patch(workload, target, images)
        print(f"{ns}/{target['name']}: {'patch' if patch else 'current'}", flush=True)
        if args.apply and patch:
            kube("-n", ns, "get", "secret", PULL_SECRET, "-o", "name")
            kube("-n", ns, "patch", target["kind"], target["name"], "--type=json", "-p", json.dumps(patch))


if __name__ == "__main__":
    main()
