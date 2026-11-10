#!/usr/bin/env python3
"""Migrate only GitOps definitions into a separately provisioned Argo CD instance."""

import argparse
import base64
import copy
import json
from pathlib import Path
import subprocess
import sys
import time

import yaml

sys.dont_write_bytecode = True
import run_live as live


TARGET_NS = "crane-gitops-target"
CLUSTER_NAME = "kind-workloads"
KINDS = {"Application", "ApplicationSet", "AppProject"}


def workloads():
    return live.workload_namespaces("filtered")


def instance_state(target):
    instance = target.get("argocd", TARGET_NS, "crane")
    default = target.get("appproject", TARGET_NS, "default")
    return {
        "uid": instance["metadata"]["uid"],
        "generation": instance["metadata"]["generation"],
        "spec": instance["spec"],
        "default_project": {"uid": default["metadata"]["uid"], "spec": default["spec"]},
        "argocd_secret_uid": target.get("secret", TARGET_NS, "argocd-secret")["metadata"]["uid"],
        "cluster_registration_uid": target.get("secret", TARGET_NS, "workloads")["metadata"]["uid"],
        "repository_secret_uid": target.get("secret", TARGET_NS, "sample-repo")["metadata"]["uid"],
        "deployment_uids": {
            obj["metadata"]["name"]: obj["metadata"]["uid"]
            for obj in target.get("deployments", TARGET_NS)["items"]
        },
    }


def prepare(options, source, target):
    # Reuse the first experiment's running instance. Only its known demo
    # Applications, ApplicationSet, and sample project are reset.
    live.wait_instance(target, TARGET_NS)
    before = instance_state(target)
    apps = {obj["metadata"]["name"] for obj in target.get("applications", TARGET_NS)["items"]}
    appsets = {obj["metadata"]["name"] for obj in target.get("applicationsets", TARGET_NS)["items"]}
    if not apps.issubset(live.APP_NAMES) or not appsets.issubset({"fleet"}):
        raise RuntimeError("Unexpected application definitions; refusing to reset this namespace")
    target.call("delete", "applicationset", "fleet", "-n", TARGET_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    target.call("delete", "applications", *sorted(live.APP_NAMES), "-n", TARGET_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    target.call("delete", "appproject", "crane-sample", "-n", TARGET_NS,
                "--ignore-not-found", "--timeout=120s", visible=True)
    registration = target.get("secret", TARGET_NS, "workloads")["data"]
    if base64.b64decode(registration["name"]).decode() != CLUSTER_NAME:
        raise AssertionError("Expected the preconfigured kind-workloads registration")
    target.apply([live.namespace(ns, TARGET_NS) for ns in workloads()])
    for ns in workloads():
        if target.get("deployments", ns)["items"]:
            raise AssertionError(f"Expected an empty workload namespace: {ns}")
    if target.get("applications", TARGET_NS)["items"] or target.get("applicationsets", TARGET_NS)["items"]:
        raise AssertionError("Target must have no application definitions before migration")
    if instance_state(target) != before:
        raise AssertionError("Reset changed the existing Argo CD installation")
    live.save(options.work_dir / "instance-before.json", before)
    live.save(options.work_dir / "source-before.json", live.instance_snapshot(source, "source"))
    print("Existing target instance and credentials preserved; demo definitions reset and workload namespaces empty", flush=True)


def crane(options, *args):
    command = [str(options.crane), *args, "--audit-log", str(options.work_dir / "crane-audit.log")]
    result = subprocess.run(command, capture_output=True, text=True, timeout=240)
    with (options.work_dir / "commands.log").open("a") as log:
        log.write(json.dumps(command) + "\n" + result.stdout + result.stderr + "\n")
    if result.returncode:
        raise RuntimeError(result.stderr)
    print(result.stdout + result.stderr, end="", flush=True)


def documents(path):
    return [doc for doc in yaml.safe_load_all(path.read_text()) if doc]


def migrate(options, source, target):
    before = json.loads((options.work_dir / "instance-before.json").read_text())
    if instance_state(target) != before:
        raise AssertionError("Target instance changed after provisioning")
    if target.get("applications", TARGET_NS)["items"] or target.get("applicationsets", TARGET_NS)["items"]:
        raise AssertionError("Expected an empty application-definition namespace")
    work = options.work_dir
    export, transform = work / "export", work / "transform"
    crane(options, "export", "--context", options.source_context, "-n", live.SOURCE_NS,
          "--include-gk", "argoproj.io/Application", "--include-gk", "argoproj.io/ApplicationSet",
          "--include-gk", "argoproj.io/AppProject", "--crd-skip-group", "argoproj.io",
          "--export-dir", str(export))
    exported = [doc for path in (export / "resources").rglob("*.yaml") for doc in documents(path)]
    failures = list((export / "failures").rglob("*.yaml"))
    if failures or len(exported) != 7 or any(doc["kind"] not in KINDS for doc in exported):
        raise AssertionError("Unexpected filtered export inventory or failures")
    crane(options, "transform", "KubernetesPlugin", "--export-dir", str(export), "--transform-dir", str(transform))
    crane(options, "apply", "--transform-dir", str(transform), "--output-dir", str(work / "baseline"))
    baseline = documents(work / "baseline/output.yaml")
    if len(baseline) != 5 or any(doc["metadata"]["name"] in {"fleet-blue", "fleet-green"} for doc in baseline):
        raise AssertionError("Expected five baseline CRs without generated children")
    # Keep the existing target default project rather than importing the source default.
    selected = [doc for doc in baseline if not (doc["kind"] == "AppProject" and doc["metadata"]["name"] == "default")]
    stage = transform / "50_FilteredTarget"
    stage.mkdir()
    resources, patches = [], []
    for doc in selected:
        filename = f"{doc['kind']}_{doc['metadata']['name']}.yaml"
        live.save(stage / filename, [doc])
        resources.append(filename)
        if doc["kind"] == "AppProject":
            operations = [
                {"op": "replace", "path": "/spec/sourceRepos", "value": [live.TARGET_REPO]},
                {"op": "replace", "path": "/spec/destinations", "value": [
                    {"server": live.LOCAL_API, "namespace": ns} for ns in workloads()
                ]},
            ]
        elif doc["kind"] == "Application":
            operations = [
                {"op": "replace", "path": "/spec/source/repoURL", "value": live.TARGET_REPO},
                {"op": "replace", "path": "/spec/source/path", "value": "overlays/target"},
                {"op": "replace", "path": "/spec/destination/server", "value": live.LOCAL_API},
                {"op": "replace", "path": "/spec/destination/namespace",
                 "value": doc["spec"]["destination"]["namespace"].replace("-source", "-filtered")},
                {"op": "remove", "path": "/spec/syncPolicy/automated"},
            ]
            if "operation" in doc:
                operations.append({"op": "remove", "path": "/operation"})
        else:
            template = copy.deepcopy(doc["spec"]["template"])
            template["spec"]["source"].update(repoURL=live.TARGET_REPO, path="overlays/target")
            template["spec"]["destination"]["name"] = CLUSTER_NAME
            template["spec"]["syncPolicy"].pop("automated", None)
            elements = copy.deepcopy(doc["spec"]["generators"][0]["list"]["elements"])
            for element in elements:
                element["namespace"] = element["namespace"].replace("-source", "-filtered")
            operations = [
                {"op": "replace", "path": "/spec/template", "value": template},
                {"op": "replace", "path": "/spec/generators/0/list/elements", "value": elements},
            ]
        patches.append({"target": {"kind": doc["kind"], "name": doc["metadata"]["name"]},
                        "patch": yaml.safe_dump(operations)})
    live.save(stage / "kustomization.yaml", [{
        "apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization",
        "namespace": TARGET_NS, "resources": resources, "patches": patches,
    }])
    crane(options, "apply", "50_FilteredTarget", "--transform-dir", str(transform),
          "--output-dir", str(work / "target-output"))
    output = documents(work / "target-output/output.yaml")
    if len(output) != 4 or any(doc["kind"] not in KINDS for doc in output):
        raise AssertionError("The target bundle must contain only four GitOps definition CRs")
    for doc in output:
        if "-source" in yaml.safe_dump(doc) or doc["metadata"].get("ownerReferences"):
            raise AssertionError("Unexpected source reference in target bundle")
    target.apply(output, dry_run=True)
    target.apply(output)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        apps = live.wait_apps(target, TARGET_NS, synced=False)
        if all(app.get("status", {}).get("sync", {}).get("status") == "OutOfSync" for app in apps.values()):
            break
        time.sleep(3)
    else:
        raise AssertionError("Expected rendered, unsynced Applications before manual sync")
    for app in apps.values():
        if "automated" in app["spec"].get("syncPolicy", {}):
            raise AssertionError("Automated sync was not paused")
    for ns in workloads():
        if target.get("deployments", ns)["items"]:
            raise AssertionError("Workload started before manual sync")
    if instance_state(target) != before:
        raise AssertionError("Migration modified the pre-existing Argo CD installation")
    live.save(work / "inventory.json", {
        "exported": [live.identity(doc) for doc in exported],
        "baseline": [live.identity(doc) for doc in baseline],
        "migrated": [live.identity(doc) for doc in output],
        "export_failure_files": [], "paused_before_sync": True,
    })
    print("PASS: filtered definitions restored, sync paused, pre-existing Argo CD unchanged", flush=True)


def verify(options, source, target):
    for name in sorted(live.APP_NAMES):
        target.call("patch", "application", name, "-n", TARGET_NS, "--type=merge", "-p", json.dumps({
            "operation": {"initiatedBy": {"username": "crane-filtered-test"}, "sync": {"prune": False}},
        }), visible=True)
    live.wait_apps(target, TARGET_NS)
    for name in sorted(live.APP_NAMES):
        target.call("annotate", "application", name, "-n", TARGET_NS,
                    "argocd.argoproj.io/refresh=hard", "--overwrite", visible=True)
        live.wait_refresh(target, TARGET_NS, "application", name, "argocd.argoproj.io/refresh")
    annotation = "argocd.argoproj.io/application-set-refresh"
    target.call("annotate", "applicationset", "fleet", "-n", TARGET_NS,
                f"{annotation}=true", "--overwrite", visible=True)
    live.wait_refresh(target, TARGET_NS, "applicationset", "fleet", annotation)
    apps = live.wait_apps(target, TARGET_NS)
    parent = target.get("applicationset", TARGET_NS, "fleet")["metadata"]["uid"]
    for name, app in apps.items():
        if "automated" in app["spec"].get("syncPolicy", {}):
            raise AssertionError("Reconciliation re-enabled automated sync")
        if name.startswith("fleet-") and app["metadata"]["ownerReferences"][0]["uid"] != parent:
            raise AssertionError("Generated child has wrong parent")
    responses = {}
    for ns in workloads():
        body = target.call("exec", "-n", ns, "deployment/sample-web", "--", "wget", "-qO-",
                           "http://127.0.0.1:8080/").strip()
        if body != "crane-argocd-live-test environment=target cluster=kind":
            raise AssertionError(f"Unexpected response in {ns}: {body}")
        responses[ns] = body
        print(f"{ns}: {body}", flush=True)
    before = json.loads((options.work_dir / "instance-before.json").read_text())
    if instance_state(target) != before:
        raise AssertionError("Target installation changed during migration or sync")
    live.wait_apps(source, live.SOURCE_NS)
    source_before = json.loads((options.work_dir / "source-before.json").read_text())
    if live.instance_snapshot(source, "source") != source_before:
        raise AssertionError("Source workloads changed")
    inventory = json.loads((options.work_dir / "inventory.json").read_text())
    live.save(options.work_dir / "filtered-results.json", {
        "target_namespace": TARGET_NS, "instance_unchanged": True,
        "instance_uid": before["uid"], "instance_generation": before["generation"],
        "existing_default_project_preserved": True, "source_workloads_unchanged": True,
        "target_responses": responses, "inventory": inventory,
        "applications": {name: {"sync": app["status"]["sync"]["status"],
                                "health": app["status"]["health"]["status"],
                                "destination": app["spec"]["destination"]} for name, app in apps.items()},
    })
    print("PASS: four apps healthy/synced using existing Argo CD; instance, default project, and source unchanged", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["prepare", "migrate", "verify"])
    parser.add_argument("--source-context", default="minikube")
    parser.add_argument("--target-context", default="kind-crane-argocd-target")
    parser.add_argument("--target-kubeconfig", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--crane", type=Path, required=True)
    options = parser.parse_args()
    options.work_dir = options.work_dir.resolve()
    options.work_dir.mkdir(parents=True, exist_ok=True)
    options.work_dir.chmod(0o700)
    options.crane = options.crane.resolve()
    source = live.Cluster(options.source_context)
    target = live.Cluster(options.target_context, options.target_kubeconfig.resolve())
    {"prepare": prepare, "migrate": migrate, "verify": verify}[options.phase](options, source, target)
