#!/usr/bin/env python3
"""Disposable minikube-to-kind Argo CD migration experiment, not a Crane plugin."""

import argparse
import base64
import copy
import json
import os
from pathlib import Path
import subprocess
import time

import yaml


ROOT = Path(__file__).resolve().parent
SOURCE_NS = "crane-gitops-source"
TARGET_NS = "crane-gitops-target"
SOURCE_REPO = "git://git-fixture.crane-git-source.svc.cluster.local:9418/apps.git"
TARGET_REPO = "git://git-fixture.crane-git-target.svc.cluster.local:9418/apps.git"
LOCAL_API = "https://kubernetes.default.svc"
APP_NAMES = {"local-web", "explicit-web", "fleet-blue", "fleet-green"}


def run(args, text=None, visible=False, timeout=180):
    result = subprocess.run(args, input=text, text=True, capture_output=True, timeout=timeout)
    if visible and result.stdout:
        print(result.stdout.strip(), flush=True)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args}\n{result.stderr}")
    return result.stdout


class Cluster:
    def __init__(self, context, kubeconfig=None):
        self.args = ["kubectl", "--context", context]
        if kubeconfig:
            self.args += ["--kubeconfig", str(kubeconfig)]

    def call(self, *args, **kwargs):
        return run(self.args + list(args), **kwargs)

    def get(self, resource, namespace=None, name=None):
        args = ["get", resource]
        if name:
            args.append(name)
        if namespace:
            args += ["-n", namespace]
        return json.loads(self.call(*args, "-o", "json"))

    def apply(self, documents, dry_run=False):
        args = ["apply", "-f", "-"]
        if dry_run:
            args.append("--dry-run=server")
        return self.call(*args, text=yaml.safe_dump_all(documents), visible=True)


def save(path, value):
    path.write_text(yaml.safe_dump_all(value) if isinstance(value, list) else json.dumps(value, indent=2) + "\n")
    path.chmod(0o600)


def namespace(name, managed_by=None):
    metadata = {"name": name}
    if managed_by:
        metadata["labels"] = {"argocd.argoproj.io/managed-by": managed_by}
    return {"apiVersion": "v1", "kind": "Namespace", "metadata": metadata}


def workload_namespaces(environment):
    return [f"crane-payments-{environment}", f"crane-ledger-{environment}"] + [
        f"crane-fleet-{environment}-{color}" for color in ["blue", "green"]
    ]


def wait_instance(cluster, ns):
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        instance = cluster.get("argocd", ns, "crane")
        if instance.get("status", {}).get("phase") == "Available":
            print(f"Argo CD instance available in {ns}", flush=True)
            return
        time.sleep(5)
    cluster.call("get", "pods", "-n", ns, visible=True)
    raise RuntimeError(f"Argo CD instance did not become available: {instance.get('status')}")


def wait_apps(cluster, ns, synced=True):
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        applications = cluster.get("applications", ns)["items"]
        apps = {app["metadata"]["name"]: app for app in applications}
        if set(apps) == APP_NAMES:
            if not synced or all(
                app.get("status", {}).get("sync", {}).get("status") == "Synced"
                and app.get("status", {}).get("health", {}).get("status") == "Healthy"
                for app in apps.values()
            ):
                print(f"Applications in {ns}: " + ", ".join(sorted(apps)), flush=True)
                return apps
        time.sleep(5)
    summary = {
        name: {"sync": app.get("status", {}).get("sync"),
               "health": app.get("status", {}).get("health"),
               "conditions": app.get("status", {}).get("conditions")}
        for name, app in apps.items()
    }
    raise RuntimeError(f"Applications did not reach expected state: {json.dumps(summary, indent=2)}")


def wait_refresh(cluster, ns, resource, name, annotation):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        obj = cluster.get(resource, ns, name)
        if annotation not in obj["metadata"].get("annotations", {}):
            return
        time.sleep(2)
    raise RuntimeError(f"Controller did not acknowledge refresh of {resource}/{name} in {ns}")


def prepare_git(cluster, environment):
    ns = f"crane-git-{environment}"
    cluster.apply([namespace(ns)])
    cluster.call("apply", "-n", ns, "-f", str(ROOT / "git-fixture.yaml"), visible=True)
    cluster.call("rollout", "status", "deployment/git-fixture", "-n", ns,
                 "--timeout=240s", visible=True, timeout=260)


def cluster_secret(cluster, ns, name, server):
    account = "crane-argocd-application-controller"
    token = cluster.call("create", "token", account, "-n", ns, "--duration=4h").strip()
    ca = cluster.get("configmap", ns, "kube-root-ca.crt")["data"]["ca.crt"]
    config = {"bearerToken": token, "tlsClientConfig": {
        "insecure": False, "caData": base64.b64encode(ca.encode()).decode(),
    }}
    return {
        "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
        "metadata": {"name": "workloads", "namespace": ns,
                     "labels": {"argocd.argoproj.io/secret-type": "cluster"}},
        "stringData": {"name": name, "server": server, "config": json.dumps(config)},
    }


def instance_snapshot(cluster, environment):
    result = {}
    for ns in workload_namespaces(environment):
        deployment = cluster.get("deployment", ns, "sample-web")
        body = cluster.call("exec", "-n", ns, "deployment/sample-web", "--", "wget", "-qO-",
                            "http://127.0.0.1:8080/").strip()
        expected = f"crane-argocd-live-test environment={environment} cluster="
        if expected not in body:
            raise AssertionError(f"Unexpected web response in {ns}: {body}")
        result[ns] = {"uid": deployment["metadata"]["uid"], "body": body,
                      "readyReplicas": deployment.get("status", {}).get("readyReplicas", 0)}
        print(f"{ns}: {body}", flush=True)
    return result


def setup_source(options, source):
    prepare_git(source, "source")
    docs = list(yaml.safe_load_all((ROOT / "source.yaml").read_text()))
    source.apply([doc for doc in docs if doc["kind"] in {"Namespace", "ArgoCD"}])
    source.apply([namespace(ns, SOURCE_NS) for ns in workload_namespaces("source")])
    wait_instance(source, SOURCE_NS)
    api = json.loads(source.call("config", "view", "--minify", "-o", "json"))["clusters"][0]["cluster"]["server"]
    source.apply([cluster_secret(source, SOURCE_NS, "minikube-workloads", api)])
    source.apply([{
        "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
        "metadata": {"name": "sample-repo", "namespace": SOURCE_NS,
                     "labels": {"argocd.argoproj.io/secret-type": "repository"}},
        "stringData": {"type": "git", "url": SOURCE_REPO},
    }])
    definitions = [doc for doc in docs if doc["kind"] not in {"Namespace", "ArgoCD"}]
    definitions = list(yaml.safe_load_all(yaml.safe_dump_all(definitions).replace("SOURCE_API_URL", api)))
    source.apply(definitions)
    wait_apps(source, SOURCE_NS)
    save(options.work_dir / "source-snapshot.json", instance_snapshot(source, "source"))
    print("Source setup and HTTP validation complete", flush=True)


def identity(doc):
    return doc["apiVersion"], doc["kind"], doc["metadata"].get("namespace", ""), doc["metadata"]["name"]


def migrate(options, source, target):
    prepare_git(target, "target")
    work = options.work_dir
    export_dir, transform_dir = work / "export", work / "transform"
    # Export the complete instance namespace, including operator-generated resources.
    crane_args = [str(options.crane), "--audit-log", str(work / "crane-audit.log")]
    run(crane_args + ["export", "--context", options.source_context, "-n", SOURCE_NS,
                     "--export-dir", str(export_dir)], visible=True, timeout=240)
    run(crane_args + ["transform", "KubernetesPlugin", "--export-dir", str(export_dir),
                     "--transform-dir", str(transform_dir)], visible=True)
    run(crane_args + ["apply", "--transform-dir", str(transform_dir),
                     "--output-dir", str(work / "baseline")], visible=True)
    baseline = [doc for doc in yaml.safe_load_all((work / "baseline/output.yaml").read_text()) if doc]
    export_objects = []
    for path in (export_dir / "resources").rglob("*.yaml"):
        export_objects.extend(doc for doc in yaml.safe_load_all(path.read_text()) if doc)
    save(work / "inventory.json", {
        "exported": [identity(doc) for doc in export_objects],
        "baseline": [identity(doc) for doc in baseline],
        "export_failure_files": [str(path.relative_to(export_dir)) for path in (export_dir / "failures").rglob("*.yaml")],
    })

    # Explicitly select desired state. Do not reapply generated RBAC, CRDs, tokens,
    # operator TLS keys, signing keys, or generated default configuration.
    allowed = {
        ("ArgoCD", "crane"), ("AppProject", "crane-sample"),
        ("Application", "local-web"), ("Application", "explicit-web"),
        ("ApplicationSet", "fleet"), ("Secret", "sample-repo"),
    }
    selected = [doc for doc in baseline if (doc["kind"], doc["metadata"]["name"]) in allowed]
    if len(selected) != len(allowed):
        raise AssertionError(f"Missing selected baseline objects: {[identity(doc) for doc in selected]}")
    stage = transform_dir / "50_ArgoTarget"
    stage.mkdir()
    resources = []
    patches = []
    for doc in selected:
        # These are materialized KubernetesPlugin output, not raw export objects.
        filename = f"{doc['kind']}_{doc['metadata']['name']}.yaml"
        path = stage / filename
        save(path, [doc])
        resources.append(filename)
        operations = []
        if doc["kind"] == "Secret":
            operations += [{"op": "remove", "path": "/data"},
                           {"op": "add", "path": "/stringData", "value": {"type": "git", "url": TARGET_REPO}}]
        elif doc["kind"] == "AppProject":
            operations += [
                {"op": "replace", "path": "/spec/sourceRepos", "value": [TARGET_REPO]},
                {"op": "replace", "path": "/spec/destinations", "value": [
                    {"server": LOCAL_API, "namespace": ns} for ns in workload_namespaces("target")
                ]},
            ]
        elif doc["kind"] == "Application":
            operations += [
                {"op": "replace", "path": "/spec/source/repoURL", "value": TARGET_REPO},
                {"op": "replace", "path": "/spec/source/path", "value": "overlays/target"},
                {"op": "replace", "path": "/spec/destination/server", "value": LOCAL_API},
                {"op": "replace", "path": "/spec/destination/namespace",
                 "value": doc["spec"]["destination"]["namespace"].replace("-source", "-target")},
                {"op": "remove", "path": "/spec/syncPolicy/automated"},
            ]
            if "operation" in doc:
                operations.append({"op": "remove", "path": "/operation"})
        elif doc["kind"] == "ApplicationSet":
            template = copy.deepcopy(doc["spec"]["template"])
            template["spec"]["source"].update(repoURL=TARGET_REPO, path="overlays/target")
            template["spec"]["destination"]["name"] = "kind-workloads"
            template["spec"]["syncPolicy"].pop("automated", None)
            elements = copy.deepcopy(doc["spec"]["generators"][0]["list"]["elements"])
            for element in elements:
                element["namespace"] = element["namespace"].replace("-source", "-target")
            operations += [
                {"op": "replace", "path": "/spec/template", "value": template},
                {"op": "replace", "path": "/spec/generators/0/list/elements", "value": elements},
            ]
        if operations:
            patches.append({"target": {"kind": doc["kind"], "name": doc["metadata"]["name"]},
                            "patch": yaml.safe_dump(operations)})
    save(stage / "kustomization.yaml", [{
        "apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization",
        "namespace": TARGET_NS, "resources": resources, "patches": patches,
    }])
    run(crane_args + ["apply", "50_ArgoTarget", "--transform-dir", str(transform_dir),
                     "--output-dir", str(work / "target-output")], visible=True)
    output = [doc for doc in yaml.safe_load_all((work / "target-output/output.yaml").read_text()) if doc]
    if len(output) != len(allowed):
        raise AssertionError("Unexpected target manifest count")
    for doc in output:
        if "-source" in yaml.safe_dump(doc) or "minikube-workloads" in yaml.safe_dump(doc):
            raise AssertionError(f"Source reference survived: {identity(doc)}")
        if doc["metadata"].get("ownerReferences"):
            raise AssertionError(f"Source ownership survived: {identity(doc)}")
    target.apply([namespace(TARGET_NS)])
    target.apply([namespace(ns, TARGET_NS) for ns in workload_namespaces("target")])
    instance = [doc for doc in output if doc["kind"] == "ArgoCD"]
    target.apply(instance, dry_run=True)
    target.apply(instance)
    wait_instance(target, TARGET_NS)
    secret = cluster_secret(target, TARGET_NS, "kind-workloads", LOCAL_API)
    save(work / "target-cluster-secret.yaml", [secret])
    target.apply([secret])
    definitions = [doc for doc in output if doc["kind"] != "ArgoCD"]
    target.apply(definitions, dry_run=True)
    target.apply(definitions)
    apps = wait_apps(target, TARGET_NS, synced=False)
    for name, app in apps.items():
        if "automated" in app["spec"].get("syncPolicy", {}):
            raise AssertionError(f"Unexpected automated sync for {name}")
    # Wait through reconciliation and prove no workload Deployments started.
    time.sleep(20)
    for ns in workload_namespaces("target"):
        if target.get("deployments", ns)["items"]:
            raise AssertionError(f"Workload started before deliberate sync in {ns}")
    print("Target instance and four Applications restored with sync paused; no workloads deployed", flush=True)


def verify(options, source, target):
    # Request a single explicit sync through the Kubernetes Application API.
    for name in sorted(APP_NAMES):
        target.call("patch", "application", name, "-n", TARGET_NS, "--type=merge", "-p", json.dumps({
            "operation": {"initiatedBy": {"username": "crane-live-test"}, "sync": {"prune": False}},
        }), visible=True)
    apps = wait_apps(target, TARGET_NS)
    target_snapshot = instance_snapshot(target, "target")
    # Refresh both controllers to check source isolation and another reconciliation.
    for cluster, ns in [(source, SOURCE_NS), (target, TARGET_NS)]:
        for name in sorted(APP_NAMES):
            cluster.call("annotate", "application", name, "-n", ns,
                         "argocd.argoproj.io/refresh=hard", "--overwrite", visible=True)
        for name in sorted(APP_NAMES):
            wait_refresh(cluster, ns, "application", name, "argocd.argoproj.io/refresh")
    refresh = "argocd.argoproj.io/application-set-refresh"
    target.call("annotate", "applicationset", "fleet", "-n", TARGET_NS,
                f"{refresh}=true", "--overwrite", visible=True)
    wait_refresh(target, TARGET_NS, "applicationset", "fleet", refresh)
    wait_apps(source, SOURCE_NS)
    apps = wait_apps(target, TARGET_NS)
    source_parent = source.get("applicationset", SOURCE_NS, "fleet")["metadata"]["uid"]
    target_parent = target.get("applicationset", TARGET_NS, "fleet")["metadata"]["uid"]
    if source_parent == target_parent:
        raise AssertionError("ApplicationSet target UID should be newly generated")
    for name, app in apps.items():
        if "automated" in app["spec"].get("syncPolicy", {}):
            raise AssertionError(f"Reconciliation re-enabled automated sync for {name}")
        if name.startswith("fleet-"):
            refs = app["metadata"].get("ownerReferences", [])
            if len(refs) != 1 or refs[0]["uid"] != target_parent:
                raise AssertionError(f"Generated Application has wrong parent: {name}")
    original = json.loads((options.work_dir / "source-snapshot.json").read_text())
    current = instance_snapshot(source, "source")
    if current != original:
        raise AssertionError("Source Deployment identity, readiness, or HTTP content changed")
    inventory = json.loads((options.work_dir / "inventory.json").read_text())
    report = {
        "source_context": options.source_context, "target_context": options.target_context,
        "source_appset_uid": source_parent, "target_appset_uid": target_parent,
        "controller_refreshes_acknowledged": True,
        "exported_resource_count": len(inventory["exported"]),
        "baseline_resource_count": len(inventory["baseline"]),
        "selected_migration_resource_count": 6,
        "export_failure_files": inventory["export_failure_files"],
        "source": current, "target": target_snapshot,
        "applications": {
            name: {"sync": app["status"]["sync"]["status"], "health": app["status"]["health"]["status"],
                   "destination": app["spec"]["destination"], "source": app["spec"]["source"],
                   "ownerReferences": app["metadata"].get("ownerReferences", [])}
            for name, app in apps.items()
        },
    }
    save(options.work_dir / "live-results.json", report)
    print(f"Exported {len(inventory['exported'])} resources; generic baseline retained {len(inventory['baseline'])}; migrated 6 selected resources", flush=True)
    print("PASS: four target apps Synced/Healthy, target HTTP content correct, source unchanged", flush=True)


def refresh_credentials(source, target):
    api = json.loads(source.call("config", "view", "--minify", "-o", "json"))["clusters"][0]["cluster"]["server"]
    source.apply([cluster_secret(source, SOURCE_NS, "minikube-workloads", api)])
    target.apply([cluster_secret(target, TARGET_NS, "kind-workloads", LOCAL_API)])
    print("Refreshed disposable cluster registration tokens", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["source", "migrate", "verify", "refresh-credentials"])
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
    source = Cluster(options.source_context)
    target = Cluster(options.target_context, options.target_kubeconfig.resolve())
    {"source": lambda: setup_source(options, source),
     "migrate": lambda: migrate(options, source, target),
     "verify": lambda: verify(options, source, target),
     "refresh-credentials": lambda: refresh_credentials(source, target)}[options.phase]()
