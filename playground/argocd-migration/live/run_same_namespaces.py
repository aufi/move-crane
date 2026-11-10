#!/usr/bin/env python3
"""Live migration with identical namespace/Git settings and minimal destination patches."""

import argparse
import json
from pathlib import Path
import shutil
import sys

import yaml

sys.dont_write_bytecode = True
import run_live as live
import run_filtered as filtered


SHARED_NS = "crane-gitops-target"
GIT_NS = "crane-git-shared"
REPO = f"git://git-fixture.{GIT_NS}.svc.cluster.local:9418/apps.git"
BODY = "crane-argocd-live-test same-namespaces shared-content"
WORKLOADS = ["crane-payments-shared", "crane-ledger-shared",
             "crane-fleet-shared-blue", "crane-fleet-shared-green"]
SELECTED = {("AppProject", "crane-sample"), ("Application", "local-web"),
            ("Application", "explicit-web"), ("ApplicationSet", "fleet")}
EXPECTED_DIFFS = {
    ("AppProject", "crane-sample"): {"/destinations/1/server", "/destinations/2/server"},
    ("Application", "local-web"): set(),
    ("Application", "explicit-web"): {"/destination/server"},
    ("ApplicationSet", "fleet"): {"/template/spec/destination/name"},
}


def git_fixture(cluster):
    cluster.apply([live.namespace(GIT_NS)])
    docs = filtered.documents(live.ROOT / "git-fixture.yaml")
    docs[0]["data"]["source-index.html"] = BODY + "\n"
    docs[0]["data"]["target-index.html"] = BODY + "\n"
    for doc in docs:
        doc["metadata"]["namespace"] = GIT_NS
    cluster.apply(docs)
    cluster.call("rollout", "status", "deployment/git-fixture", "-n", GIT_NS,
                 "--timeout=240s", visible=True, timeout=260)


def snapshot(cluster):
    result = {}
    for ns in WORKLOADS:
        deployment = cluster.get("deployment", ns, "sample-web")
        body = cluster.call("exec", "-n", ns, "deployment/sample-web", "--", "wget", "-qO-",
                            "http://127.0.0.1:8080/").strip()
        if body != BODY:
            raise AssertionError(f"Wrong HTTP content in {ns}: {body}")
        result[ns] = {"uid": deployment["metadata"]["uid"], "body": body,
                      "readyReplicas": deployment.get("status", {}).get("readyReplicas", 0)}
        if result[ns]["readyReplicas"] != 1:
            raise AssertionError(f"Workload is not ready in {ns}")
        print(f"{ns}: {body}", flush=True)
    return result


def prepare(options, source, target):
    # A separate source instance uses the already-running target's namespace name.
    # Existing source examples in crane-gitops-source are left running.
    git_fixture(source)
    git_fixture(target)
    namespaces = source.get("namespaces")["items"]
    existing = next((ns for ns in namespaces if ns["metadata"]["name"] == SHARED_NS), None)
    if existing and existing["metadata"].get("labels", {}).get("crane-test") != "same-namespaces":
        raise RuntimeError("Source namespace already exists outside this experiment")
    source_ns = live.namespace(SHARED_NS)
    source_ns["metadata"]["labels"] = {"crane-test": "same-namespaces"}
    source.apply([source_ns])
    source.apply([{
        "apiVersion": "argoproj.io/v1beta1", "kind": "ArgoCD",
        "metadata": {"name": "crane", "namespace": SHARED_NS},
        "spec": {"applicationSet": {"enabled": True}, "server": {"insecure": True}},
    }])
    source.apply([live.namespace(ns, SHARED_NS) for ns in WORKLOADS])
    live.wait_instance(source, SHARED_NS)
    api = json.loads(source.call("config", "view", "--minify", "-o", "json"))["clusters"][0]["cluster"]["server"]
    source.apply([live.cluster_secret(source, SHARED_NS, "minikube-workloads", api)])
    docs = [doc for doc in filtered.documents(live.ROOT / "source.yaml") if doc["kind"] in filtered.KINDS]
    namespace_map = dict(zip(live.workload_namespaces("source"), WORKLOADS))
    for doc in docs:
        doc["metadata"]["namespace"] = SHARED_NS
        if doc["kind"] == "AppProject":
            doc["spec"]["sourceRepos"] = [REPO]
            doc["spec"]["destinations"] = [
                {"server": live.LOCAL_API, "namespace": WORKLOADS[0]},
                {"server": api, "namespace": WORKLOADS[1]},
                {"server": live.LOCAL_API if options.portable_fleet else api,
                 "namespace": "crane-fleet-shared-*"},
            ]
        elif doc["kind"] == "Application":
            doc["spec"]["source"]["repoURL"] = REPO
            doc["spec"]["destination"]["namespace"] = namespace_map[doc["spec"]["destination"]["namespace"]]
            if doc["metadata"]["name"] == "explicit-web":
                doc["spec"]["destination"]["server"] = api
        else:
            doc["spec"]["template"]["spec"]["source"]["repoURL"] = REPO
            if options.portable_fleet:
                doc["spec"]["template"]["spec"]["destination"] = {
                    "server": live.LOCAL_API, "namespace": "{{namespace}}",
                }
            for element in doc["spec"]["generators"][0]["list"]["elements"]:
                element["namespace"] = namespace_map[element["namespace"]]
    source.apply(docs)
    live.wait_apps(source, SHARED_NS)
    live.save(options.work_dir / "source-before.json", snapshot(source))
    live.save(options.work_dir / "original-source-before.json", live.instance_snapshot(source, "source"))

    # Reset only the known demo definitions in the pre-existing target instance.
    live.wait_instance(target, SHARED_NS)
    before = filtered.instance_state(target)
    apps = {obj["metadata"]["name"] for obj in target.get("applications", SHARED_NS)["items"]}
    appsets = {obj["metadata"]["name"] for obj in target.get("applicationsets", SHARED_NS)["items"]}
    if not apps.issubset(live.APP_NAMES) or not appsets.issubset({"fleet"}):
        raise RuntimeError("Unexpected target application definitions")
    target.call("delete", "applicationset", "fleet", "-n", SHARED_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    target.call("delete", "applications", *sorted(live.APP_NAMES), "-n", SHARED_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    target.call("delete", "appproject", "crane-sample", "-n", SHARED_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    target.apply([live.namespace(ns, SHARED_NS) for ns in WORKLOADS])
    if any(target.get("deployments", ns)["items"] for ns in WORKLOADS):
        raise AssertionError("Expected empty target workload namespaces")
    if filtered.instance_state(target) != before:
        raise AssertionError("Existing target installation changed during preparation")
    live.save(options.work_dir / "instance-before.json", before)
    print("Ready: identical namespace names and Git settings on both clusters", flush=True)


def differences(before, after, path=""):
    if isinstance(before, dict) and isinstance(after, dict):
        return set().union(*(differences(before.get(key), after.get(key), f"{path}/{key}")
                             for key in before.keys() | after.keys()))
    if isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        return set().union(*(differences(left, right, f"{path}/{index}")
                             for index, (left, right) in enumerate(zip(before, after))))
    return {path} if before != after else set()


def migrate(options, source, target):
    before = json.loads((options.work_dir / "instance-before.json").read_text())
    if filtered.instance_state(target) != before or target.get("applications", SHARED_NS)["items"]:
        raise AssertionError("Expected the unchanged target instance without demo Applications")
    work = options.work_dir
    export, transform = work / "export", work / "transform"
    filtered.crane(options, "export", "--context", options.source_context, "-n", SHARED_NS,
                   "--include-gk", "argoproj.io/Application", "--include-gk", "argoproj.io/ApplicationSet",
                   "--include-gk", "argoproj.io/AppProject", "--crd-skip-group", "argoproj.io",
                   "--export-dir", str(export))
    exported = [doc for path in (export / "resources").rglob("*.yaml") for doc in filtered.documents(path)]
    if len(exported) != 7 or list((export / "failures").rglob("*.yaml")):
        raise AssertionError("Unexpected export count or failures")
    if any(doc["kind"] not in filtered.KINDS for doc in exported):
        raise AssertionError("Unexpected resource kind in filtered export")
    filtered.crane(options, "transform", "KubernetesPlugin", "--export-dir", str(export), "--transform-dir", str(transform))
    filtered.crane(options, "apply", "--transform-dir", str(transform), "--output-dir", str(work / "baseline"))
    baseline = filtered.documents(work / "baseline/output.yaml")
    if len(baseline) != 5:
        raise AssertionError("Expected five baseline resources")
    selected = {(doc["kind"], doc["metadata"]["name"]): doc for doc in baseline
                if (doc["kind"], doc["metadata"]["name"]) in SELECTED}
    if set(selected) != SELECTED:
        raise AssertionError("Missing desired-state resources")
    expected_diffs = dict(EXPECTED_DIFFS)
    if options.portable_fleet:
        expected_diffs[("ApplicationSet", "fleet")] = set()
        expected_diffs[("AppProject", "crane-sample")] = {"/destinations/1/server"}
    stage_name = "50_MinimalDestinations" if options.portable_fleet else "50_SameNamespaces"
    stage = transform / stage_name
    stage.mkdir()
    for (kind, name), doc in selected.items():
        live.save(stage / f"{kind}_{name}.yaml", [doc])
    recipe = "same-namespaces/minimal/kustomization.yaml" if options.portable_fleet else "same-namespaces/kustomization.yaml"
    shutil.copyfile(live.ROOT / recipe, stage / "kustomization.yaml")
    filtered.crane(options, "apply", stage_name, "--transform-dir", str(transform),
                   "--output-dir", str(work / "target-output"))
    output = filtered.documents(work / "target-output/output.yaml")
    actual_diffs = {}
    if len(output) != 4:
        raise AssertionError("Expected four final definitions")
    for doc in output:
        key = (doc["kind"], doc["metadata"]["name"])
        changed = differences(selected[key]["spec"], doc["spec"])
        if changed != expected_diffs[key] or doc["metadata"]["namespace"] != SHARED_NS:
            raise AssertionError(f"Unexpected transformation for {key}: {changed}")
        actual_diffs[f"{key[0]}/{key[1]}"] = sorted(changed)
    live.save(work / "spec-differences.json", actual_diffs)
    target.apply(output, dry_run=True)
    target.apply(output)
    count = sum(len(paths) for paths in expected_diffs.values())
    print(f"Applied exactly {count} JSON Patch operations; automated sync remains enabled", flush=True)


def verify(options, source, target):
    apps = live.wait_apps(target, SHARED_NS)
    for name in sorted(live.APP_NAMES):
        target.call("annotate", "application", name, "-n", SHARED_NS,
                    "argocd.argoproj.io/refresh=hard", "--overwrite", visible=True)
        live.wait_refresh(target, SHARED_NS, "application", name, "argocd.argoproj.io/refresh")
    annotation = "argocd.argoproj.io/application-set-refresh"
    target.call("annotate", "applicationset", "fleet", "-n", SHARED_NS,
                f"{annotation}=true", "--overwrite", visible=True)
    live.wait_refresh(target, SHARED_NS, "applicationset", "fleet", annotation)
    apps = live.wait_apps(target, SHARED_NS)
    source_apps = live.wait_apps(source, SHARED_NS)
    parent = target.get("applicationset", SHARED_NS, "fleet")["metadata"]["uid"]
    for name, app in apps.items():
        if not app["spec"].get("syncPolicy", {}).get("automated"):
            raise AssertionError("Expected unchanged automated sync")
        if app["status"]["sync"]["revision"] != source_apps[name]["status"]["sync"]["revision"]:
            raise AssertionError("Source and target Git revisions differ")
        if app["spec"]["destination"]["namespace"] != source_apps[name]["spec"]["destination"]["namespace"]:
            raise AssertionError("Workload namespace changed")
        if options.portable_fleet and name != "explicit-web" and app["spec"] != source_apps[name]["spec"]:
            raise AssertionError(f"Portable Application spec changed: {name}")
        if name.startswith("fleet-") and app["metadata"]["ownerReferences"][0]["uid"] != parent:
            raise AssertionError("Wrong target ApplicationSet owner")
    target_snapshot = snapshot(target)
    if snapshot(source) != json.loads((options.work_dir / "source-before.json").read_text()):
        raise AssertionError("Source workloads changed")
    if live.instance_snapshot(source, "source") != json.loads((options.work_dir / "original-source-before.json").read_text()):
        raise AssertionError("Original source example changed")
    if filtered.instance_state(target) != json.loads((options.work_dir / "instance-before.json").read_text()):
        raise AssertionError("Existing target instance changed")
    live.save(options.work_dir / "same-namespace-results.json", {
        "definition_namespace_on_both_clusters": SHARED_NS, "workload_namespaces_on_both_clusters": WORKLOADS,
        "git_url_unchanged": REPO, "git_path_unchanged": "overlays/source", "automated_sync_unchanged": True,
        "portable_fleet": options.portable_fleet,
        "custom_spec_differences": json.loads((options.work_dir / "spec-differences.json").read_text()),
        "target": target_snapshot, "target_instance_preserved": True, "source_workloads_preserved": True,
        "applications": {name: {"sync": app["status"]["sync"]["status"], "health": app["status"]["health"]["status"],
                                "revision": app["status"]["sync"]["revision"]} for name, app in apps.items()},
    })
    count = sum(len(paths) for paths in json.loads((options.work_dir / "spec-differences.json").read_text()).values())
    print(f"PASS: same namespaces, unchanged Git/sync policy, {count} destination-only operations, four healthy apps", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "migrate", "verify"])
    parser.add_argument("--source-context", default="minikube")
    parser.add_argument("--target-context", default="kind-crane-argocd-target")
    parser.add_argument("--target-kubeconfig", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--crane", type=Path, required=True)
    parser.add_argument("--portable-fleet", action="store_true",
                        help="Use the local API destination for fleet and test only the two explicit-destination patches")
    options = parser.parse_args()
    options.work_dir = options.work_dir.resolve()
    options.work_dir.mkdir(parents=True, exist_ok=True)
    options.work_dir.chmod(0o700)
    options.crane = options.crane.resolve()
    source = live.Cluster(options.source_context)
    target = live.Cluster(options.target_context, options.target_kubeconfig.resolve())
    {"prepare": prepare, "migrate": migrate, "verify": verify}[options.phase](options, source, target)
