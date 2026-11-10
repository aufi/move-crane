#!/usr/bin/env python3
"""CRC fresh-cluster restore experiment with host-retained Git and Crane artifacts."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import yaml

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))
import run_live as live


NS = "crane-gitops-crc"
REPO = "git://host.crc.testing:9418/apps.git"
BODY = "crane-crc-gitops restored-shared-content"
WORKLOADS = ["crane-payments-crc", "crane-ledger-crc", "crane-fleet-crc-blue", "crane-fleet-crc-green"]
APP_NAMES = {"local-web", "explicit-web", "fleet-blue", "fleet-green"}
SELECTED = {("Application", "local-web"), ("Application", "explicit-web"),
            ("ApplicationSet", "fleet"), ("AppProject", "crane-sample")}


def private_command(options, name, args, timeout=1200):
    env = dict(os.environ, KUBECONFIG=str(options.work_dir / "crc-cli.kubeconfig"))
    result = subprocess.run(args, capture_output=True, text=True, env=env, timeout=timeout)
    path = options.work_dir / f"{name}.log"
    path.write_text(result.stdout + result.stderr)
    path.chmod(0o600)
    if result.returncode:
        raise RuntimeError(f"Command failed; inspect private log {path}")
    print(f"Completed {args[0]} {args[1]}; private log: {path}", flush=True)
    return result.stdout


def client(options, role):
    path = options.work_dir / f"{role}.kubeconfig"
    config = json.loads(path.read_text())
    cluster = live.Cluster(config["current-context"], path)
    cluster.args[0] = "oc"
    return cluster


def cluster_identity(cluster):
    return {
        "cluster_id": cluster.get("clusterversion", name="version")["spec"]["clusterID"],
        "kube_system_uid": cluster.get("namespace", name="kube-system")["metadata"]["uid"],
        "node_uids": {node["metadata"]["name"]: node["metadata"]["uid"]
                      for node in cluster.get("nodes")["items"]},
    }


def start(options, role):
    private_command(options, "host-network-access", ["crc", "config", "set", "host-network-access", "true"])
    private_command(options, f"{role}-crc-start", ["crc", "start", "--memory", str(options.memory),
                    "--cpus", str(options.cpus), "--disable-update-check"], timeout=1500)
    machine_config = Path.home() / ".crc/machines/crc/kubeconfig"
    config = json.loads(live.run(["oc", "--kubeconfig", str(machine_config), "config", "view", "--raw", "--flatten", "-o", "json"]))
    live.save(options.work_dir / f"{role}.kubeconfig", config)
    cluster = client(options, role)
    cluster.call("wait", "nodes", "--all", "--for=condition=Ready", "--timeout=300s", visible=True, timeout=320)
    identity = cluster_identity(cluster)
    if role == "target":
        if not (options.work_dir / "reset-complete.json").exists():
            raise AssertionError("Target startup requires the completed CRC delete phase")
        names = {item["metadata"]["name"] for item in cluster.get("namespaces")["items"]}
        if names & {NS, *WORKLOADS}:
            raise AssertionError("Fresh target unexpectedly contains source test namespaces")
        # CRC boots a cached cluster disk image, which can retain bundled IDs.
        # Freshness is established by delete/recreate plus absent test state.
        identity["test_namespaces_absent_before_bootstrap"] = True
    live.save(options.work_dir / f"{role}-cluster.json", identity)
    print(f"{role} API ready, kube-system UID {identity['kube_system_uid']}", flush=True)


def host_git(options):
    work = options.work_dir
    source, bare = work / "git-work", work / "git/apps.git"
    if source.exists() or bare.exists():
        raise RuntimeError("Git fixture already exists; use a fresh work directory")
    source.mkdir()
    (source / "apps").mkdir()
    shutil.copytree(ROOT / "app", source / "apps/web")
    live.run(["git", "init", "-b", "main", str(source)])
    live.run(["git", "-C", str(source), "add", "."])
    env = dict(os.environ, GIT_AUTHOR_DATE="2026-11-10T12:00:00Z", GIT_COMMITTER_DATE="2026-11-10T12:00:00Z")
    subprocess.run(["git", "-C", str(source), "-c", "user.name=Crane-test", "-c", "user.email=crane-test@example.test",
                    "-c", "commit.gpgsign=false", "commit", "-m", "Add portable OpenShift sample"],
                   env=env, capture_output=True, text=True, check=True)
    bare.parent.mkdir()
    live.run(["git", "clone", "--bare", str(source), str(bare)])
    live.run(["podman", "build", "-t", "localhost/crane-crc-git:v1", str(ROOT / "git-server")], timeout=300)
    live.run(["podman", "run", "-d", "--name", "crane-crc-git", "--label", "crane-test=crc-restore",
              "-p", "9418:9418", "-v", f"{bare.parent}:/git:ro,Z", "localhost/crane-crc-git:v1"])
    refs = live.run(["git", "ls-remote", "git://127.0.0.1:9418/apps.git"], timeout=30)
    live.save(work / "git-fixture.json", {"repo_url": REPO, "refs": refs})
    print("Host Git fixture is ready and remains outside the CRC VM", flush=True)


def instance_state(cluster):
    instance = cluster.get("argocd", NS, "crane")
    return {"uid": instance["metadata"]["uid"], "generation": instance["metadata"]["generation"],
            "spec": instance["spec"],
            "default_project_uid": cluster.get("appproject", NS, "default")["metadata"]["uid"],
            "credential_secret_uids": {name: cluster.get("secret", NS, name)["metadata"]["uid"]
                                       for name in ["argocd-secret", "workloads"]}}


def bootstrap(options, role):
    cluster = client(options, role)
    cluster.call("apply", "--server-side", "-k", str(ROOT / "operator"), visible=True, timeout=240)
    cluster.call("rollout", "status", "deployment/argocd-operator-controller-manager", "-n", "argocd-operator-system",
                 "--timeout=300s", visible=True, timeout=320)
    cluster.apply([live.namespace(NS)])
    cluster.apply([{
        "apiVersion": "argoproj.io/v1beta1", "kind": "ArgoCD",
        "metadata": {"name": "crane", "namespace": NS},
        "spec": {"applicationSet": {"enabled": True}, "server": {"insecure": True}},
    }])
    cluster.apply([live.namespace(name, NS) for name in WORKLOADS])
    live.wait_instance(cluster, NS)
    cluster.apply([live.cluster_secret(cluster, NS, "workloads", live.LOCAL_API)])
    refs = cluster.call("exec", "-n", NS, "deployment/crane-repo-server", "--", "timeout", "20", "git", "ls-remote", REPO)
    expected = json.loads((options.work_dir / "git-fixture.json").read_text())["refs"]
    if refs != expected:
        raise AssertionError("Cluster cannot read the expected host Git repository")
    live.save(options.work_dir / f"{role}-instance.json", instance_state(cluster))
    print(f"{role} operator, Argo CD, target-local registration, and host Git access ready", flush=True)


def source_definitions():
    common = {"repoURL": REPO, "targetRevision": "main", "path": "apps/web"}
    sync = {"automated": {"prune": True, "selfHeal": True}}
    docs = [{"apiVersion": "argoproj.io/v1alpha1", "kind": "AppProject",
             "metadata": {"name": "crane-sample", "namespace": NS},
             "spec": {"sourceRepos": [REPO], "destinations": [
                 {"server": live.LOCAL_API, "namespace": name} for name in WORKLOADS]}}]
    for name, destination in [
        ("local-web", {"server": live.LOCAL_API, "namespace": WORKLOADS[0]}),
        ("explicit-web", {"name": "workloads", "namespace": WORKLOADS[1]}),
    ]:
        docs.append({"apiVersion": "argoproj.io/v1alpha1", "kind": "Application",
                     "metadata": {"name": name, "namespace": NS,
                                  "finalizers": ["resources-finalizer.argocd.argoproj.io"]},
                     "spec": {"project": "crane-sample", "source": common,
                              "destination": destination, "syncPolicy": sync}})
    docs.append({"apiVersion": "argoproj.io/v1alpha1", "kind": "ApplicationSet",
                 "metadata": {"name": "fleet", "namespace": NS},
                 "spec": {"generators": [{"list": {"elements": [
                     {"name": "blue", "namespace": WORKLOADS[2]},
                     {"name": "green", "namespace": WORKLOADS[3]},
                 ]}}], "template": {"metadata": {"name": "fleet-{{name}}"}, "spec": {
                     "project": "crane-sample", "source": common,
                     "destination": {"server": live.LOCAL_API, "namespace": "{{namespace}}"},
                     "syncPolicy": sync}}}})
    return docs


def snapshot(cluster):
    result = {}
    for ns in WORKLOADS:
        deployment = cluster.get("deployment", ns, "sample-web")
        route = cluster.get("route", ns, "sample-web")
        admitted = [item for item in route.get("status", {}).get("ingress", [])
                    if any(condition["type"] == "Admitted" and condition["status"] == "True"
                           for condition in item.get("conditions", []))]
        if not admitted:
            raise AssertionError(f"Route is not admitted in {ns}")
        host = route["spec"]["host"]
        body = live.run(["curl", "--fail", "--silent", "--show-error", "--retry", "10", "--retry-all-errors",
                         "--retry-delay", "3", "--max-time", "10", f"http://{host}/"], timeout=150).strip()
        if body != BODY or deployment.get("status", {}).get("readyReplicas") != 1:
            raise AssertionError(f"Workload response or readiness failed in {ns}: {body}")
        pods = cluster.get("pods", ns)["items"]
        running = [pod for pod in pods if pod.get("status", {}).get("phase") == "Running"]
        if len(running) != 1:
            raise AssertionError(f"Expected one running sample Pod in {ns}")
        pod = running[0]
        result[ns] = {"deployment_uid": deployment["metadata"]["uid"], "route_uid": route["metadata"]["uid"],
                      "namespace_uid": cluster.get("namespace", name=ns)["metadata"]["uid"],
                      "host": host, "body": body, "pod_uid": pod["metadata"]["uid"],
                      "scc": pod["metadata"].get("annotations", {}).get("openshift.io/scc"),
                      "run_as_user": pod["spec"]["containers"][0].get("securityContext", {}).get("runAsUser")}
        print(f"{ns}: Route {host}, response {body}", flush=True)
    return result


def setup_source(options):
    cluster = client(options, "source")
    cluster.apply(source_definitions())
    apps = live.wait_apps(cluster, NS)
    live.save(options.work_dir / "source-workloads.json", snapshot(cluster))
    live.save(options.work_dir / "source-applications.json", {
        name: {"spec": app["spec"], "uid": app["metadata"]["uid"],
               "revision": app["status"]["sync"]["revision"]} for name, app in apps.items()})
    print("Source applications and all OpenShift Routes verified", flush=True)


def crane(options, *args):
    result = subprocess.run([str(options.crane), *args, "--audit-log", str(options.work_dir / "crane-audit.log")],
                            capture_output=True, text=True, timeout=240)
    with (options.work_dir / "crane-commands.log").open("a") as log:
        log.write(json.dumps(args) + "\n" + result.stdout + result.stderr + "\n")
    if result.returncode:
        raise RuntimeError("Crane command failed; inspect crane-commands.log")
    print(result.stdout + result.stderr, end="", flush=True)


def export(options):
    if not (options.work_dir / "source-workloads.json").exists():
        raise RuntimeError("Verify source workload startup before export")
    work = options.work_dir
    config = json.loads((work / "source.kubeconfig").read_text())
    crane(options, "export", "--kubeconfig", str(work / "source.kubeconfig"), "--context", config["current-context"],
          "-n", NS, "--include-gk", "argoproj.io/Application", "--include-gk", "argoproj.io/ApplicationSet",
          "--include-gk", "argoproj.io/AppProject", "--crd-skip-group", "argoproj.io", "--export-dir", str(work / "export"))
    if list((work / "export/failures").rglob("*.yaml")):
        raise AssertionError("Export reported resource failures")
    crane(options, "transform", "KubernetesPlugin", "--export-dir", str(work / "export"),
          "--transform-dir", str(work / "transform"))
    crane(options, "apply", "--transform-dir", str(work / "transform"), "--output-dir", str(work / "baseline"))
    baseline = [doc for doc in yaml.safe_load_all((work / "baseline/output.yaml").read_text()) if doc]
    selected = [doc for doc in baseline if (doc["kind"], doc["metadata"]["name"]) in SELECTED]
    if len(baseline) != 5 or len(selected) != 4:
        raise AssertionError("Unexpected baseline/selected resource counts")
    stage = work / "transform/50_SelectedDefinitions"
    stage.mkdir()
    resources = []
    for doc in selected:
        name = f"{doc['kind']}_{doc['metadata']['name']}.yaml"
        live.save(stage / name, [doc])
        resources.append(name)
    live.save(stage / "kustomization.yaml", [{"apiVersion": "kustomize.config.k8s.io/v1beta1",
              "kind": "Kustomization", "resources": resources}])
    crane(options, "apply", "50_SelectedDefinitions", "--transform-dir", str(work / "transform"),
          "--output-dir", str(work / "target-output"))
    output = [doc for doc in yaml.safe_load_all((work / "target-output/output.yaml").read_text()) if doc]
    if sorted(selected, key=live.identity) != sorted(output, key=live.identity):
        raise AssertionError("Selection-only stage changed resources")
    live.save(work / "export-ready.json", {"resources": [live.identity(doc) for doc in output],
                                          "custom_patch_operations": 0})
    print("Host export ready: four selected definitions, zero custom patch operations", flush=True)


def reset(options):
    for name in ["source-workloads.json", "source-applications.json", "export-ready.json", "git-fixture.json"]:
        if not (options.work_dir / name).exists():
            raise RuntimeError(f"Missing required host artifact before CRC deletion: {name}")
    cluster = client(options, "source")
    if cluster_identity(cluster) != json.loads((options.work_dir / "source-cluster.json").read_text()):
        raise AssertionError("Active CRC is not the recorded source cluster")
    refs = live.run(["git", "ls-remote", "git://127.0.0.1:9418/apps.git"])
    if refs != json.loads((options.work_dir / "git-fixture.json").read_text())["refs"]:
        raise AssertionError("Host Git fixture changed")
    private_command(options, "crc-stop", ["crc", "stop"], timeout=300)
    private_command(options, "crc-delete", ["crc", "delete", "--force"], timeout=300)
    live.save(options.work_dir / "reset-complete.json", {"crc_stop_completed": True, "crc_delete_completed": True,
                                                         "bundle_cache_preserved": True})
    print("Source CRC deleted; Git and export remain on the host", flush=True)


def import_definitions(options):
    cluster = client(options, "target")
    before = json.loads((options.work_dir / "target-instance.json").read_text())
    if instance_state(cluster) != before or cluster.get("applications", NS)["items"]:
        raise AssertionError("Expected the preconfigured target instance without Applications")
    output = [doc for doc in yaml.safe_load_all((options.work_dir / "target-output/output.yaml").read_text()) if doc]
    cluster.apply(output, dry_run=True)
    cluster.apply(output)
    print("Imported selected definitions into the preinstalled target Argo CD", flush=True)


def verify(options):
    cluster = client(options, "target")
    apps = live.wait_apps(cluster, NS)
    for name in sorted(APP_NAMES):
        cluster.call("annotate", "application", name, "-n", NS,
                     "argocd.argoproj.io/refresh=hard", "--overwrite", visible=True)
        live.wait_refresh(cluster, NS, "application", name, "argocd.argoproj.io/refresh")
    annotation = "argocd.argoproj.io/application-set-refresh"
    cluster.call("annotate", "applicationset", "fleet", "-n", NS, f"{annotation}=true", "--overwrite", visible=True)
    live.wait_refresh(cluster, NS, "applicationset", "fleet", annotation)
    apps = live.wait_apps(cluster, NS)
    source_apps = json.loads((options.work_dir / "source-applications.json").read_text())
    parent_uid = cluster.get("applicationset", NS, "fleet")["metadata"]["uid"]
    for name, app in apps.items():
        if app["spec"] != source_apps[name]["spec"] or app["status"]["sync"]["revision"] != source_apps[name]["revision"]:
            raise AssertionError(f"Application configuration or Git revision changed: {name}")
        if app["metadata"]["uid"] == source_apps[name]["uid"]:
            raise AssertionError("Application was not recreated")
        if name.startswith("fleet-") and app["metadata"]["ownerReferences"][0]["uid"] != parent_uid:
            raise AssertionError("Wrong target owner reference")
    target = snapshot(cluster)
    source = json.loads((options.work_dir / "source-workloads.json").read_text())
    for ns, result in target.items():
        for field in ["deployment_uid", "route_uid", "pod_uid", "namespace_uid"]:
            if result[field] == source[ns][field]:
                raise AssertionError(f"Source object survived reset: {ns}/{field}")
        if result["host"] != source[ns]["host"] or result["body"] != source[ns]["body"]:
            raise AssertionError("Restored Route behavior differs")
    if instance_state(cluster) != json.loads((options.work_dir / "target-instance.json").read_text()):
        raise AssertionError("Import modified the preinstalled target instance")
    source_instance = json.loads((options.work_dir / "source-instance.json").read_text())
    target_instance = instance_state(cluster)
    if source_instance["uid"] == target_instance["uid"]:
        raise AssertionError("Instance was not freshly provisioned")
    live.save(options.work_dir / "crc-results.json", {
        "custom_patch_operations": 0, "fresh_target_namespaces_verified": True,
        "source_cluster": json.loads((options.work_dir / "source-cluster.json").read_text()),
        "target_cluster": json.loads((options.work_dir / "target-cluster.json").read_text()),
        "target_instance_preserved_during_import": True, "applications_specs_unchanged": True,
        "source": source, "target": target,
        "applications": {name: {"sync": app["status"]["sync"]["status"], "health": app["status"]["health"]["status"],
                                "revision": app["status"]["sync"]["revision"]} for name, app in apps.items()},
    })
    print("PASS: fresh CRC restore, zero custom patches, four healthy Applications and working OpenShift Routes", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["host-git", "start-source", "bootstrap-source", "source", "export", "reset",
                                        "start-target", "bootstrap-target", "import", "verify"])
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--crane", type=Path, required=True)
    parser.add_argument("--memory", type=int, default=14336)
    parser.add_argument("--cpus", type=int, default=6)
    parser.add_argument("--repo-url", help="Stable Git URL reachable from CRC, recorded in the host artifact directory")
    options = parser.parse_args()
    options.work_dir = options.work_dir.resolve()
    options.work_dir.mkdir(parents=True, exist_ok=True)
    options.work_dir.chmod(0o700)
    options.crane = options.crane.resolve()
    fixture_path = options.work_dir / "git-fixture.json"
    fixture = json.loads(fixture_path.read_text()) if fixture_path.exists() else {}
    if options.repo_url:
        if (options.work_dir / "source-applications.json").exists() and options.repo_url != fixture.get("repo_url"):
            parser.error("Git URL cannot change after source validation")
        REPO = options.repo_url
        if fixture:
            fixture["repo_url"] = REPO
            live.save(fixture_path, fixture)
    elif fixture:
        REPO = fixture["repo_url"]
    elif options.phase == "host-git":
        parser.error("--repo-url is required, using a host address reachable from CRC")
    if options.phase == "host-git":
        host_git(options)
    elif options.phase.startswith("start-"):
        start(options, options.phase.removeprefix("start-"))
    elif options.phase.startswith("bootstrap-"):
        bootstrap(options, options.phase.removeprefix("bootstrap-"))
    else:
        {"source": setup_source, "export": export, "reset": reset,
         "import": import_definitions, "verify": verify}[options.phase](options)
