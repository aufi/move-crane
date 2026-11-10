#!/usr/bin/env python3
"""Run real Crane transforms against synthetic Argo CD export content."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parent
OPTIONS = None


def load_documents(path):
    return [doc for doc in yaml.safe_load_all(path.read_text()) if doc]


def index_documents(documents):
    result = {}
    for doc in documents:
        key = (doc["kind"], doc["metadata"]["name"])
        if key in result:
            raise AssertionError(f"Duplicate fixture identity: {key}")
        result[key] = doc
    return result


def secret_values(secret):
    values = {
        key: base64.b64decode(value, validate=True).decode()
        for key, value in secret.get("data", {}).items()
    }
    values.update(secret.get("stringData", {}))
    return values


def digest_tree(directory):
    return {
        str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(directory.rglob("*.yaml"))
    }


class ArgoMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = OPTIONS.work_dir
        cls.crane = OPTIONS.crane
        cls.home = cls.work / "home"
        cls.home.mkdir()
        cls.source = index_documents(load_documents(ROOT / "fixtures/source.yaml"))
        cls.fixture_hash = digest_tree(ROOT / "fixtures")
        cls.export = cls.work / "export"
        for (kind, name), doc in cls.source.items():
            directory = cls.export / "resources" / doc["metadata"]["namespace"]
            directory.mkdir(parents=True, exist_ok=True)
            (directory / f"{kind}_{name}.yaml").write_text(yaml.safe_dump(doc))
        cls.export_hash = digest_tree(cls.export)
        cls.call_number = 0
        cls.run_crane("version")
        cls.default_dir = cls.work / "default-transform"
        cls.default = cls.pipeline(cls.default_dir, cls.work / "default-output")

        cls.owned = cls.pipeline(
            cls.work / "retain-owned-transform",
            cls.work / "retain-owned-output",
            ["--optional-flags", '{"disable-whiteout-owned":"true"}'],
        )

        # A deliberately incomplete recipe to prove namespace-only remapping fails.
        namespace_stage = cls.default_dir / "40_NamespaceOnly"
        namespace_stage.mkdir()
        (namespace_stage / "kustomization.yaml").write_text(yaml.safe_dump({
            "apiVersion": "kustomize.config.k8s.io/v1beta1",
            "kind": "Kustomization",
            "resources": ["../10_KubernetesPlugin"],
            "namespace": "gitops-target",
        }))
        cls.run_crane(
            "apply", "40_NamespaceOnly", "--transform-dir", str(cls.default_dir),
            "--output-dir", str(cls.work / "namespace-only-output"),
        )
        cls.namespace_only = index_documents(load_documents(
            cls.work / "namespace-only-output/output.yaml"
        ))

        shutil.copytree(ROOT / "target-stage", cls.default_dir / "50_ArgoTarget")
        cls.target = cls.apply_target(cls.default_dir, cls.work / "target-output")

        # Rebuild from the same immutable export, rather than trusting one apply.
        replay_dir = cls.work / "replay-transform"
        cls.pipeline(replay_dir, cls.work / "replay-baseline-output")
        shutil.copytree(ROOT / "target-stage", replay_dir / "50_ArgoTarget")
        cls.replay = cls.apply_target(replay_dir, cls.work / "replay-target-output")

    @classmethod
    def run_crane(cls, *args):
        cls.call_number += 1
        env = dict(os.environ, HOME=str(cls.home), KUBECONFIG=os.devnull)
        command = [cls.crane, *args, "--audit-log", str(cls.work / "audit.log")]
        result = subprocess.run(
            command, cwd=cls.work, env=env, text=True, capture_output=True,
            timeout=120,
        )
        log = cls.work / f"command-{cls.call_number:02d}.log"
        log.write_text(
            json.dumps(command) + "\n" + result.stdout + result.stderr
        )
        if result.returncode:
            raise AssertionError(f"Crane failed, see {log}:\n{result.stderr}")

    @classmethod
    def pipeline(cls, transform, output, extra_flags=()):
        cls.run_crane(
            "transform", "KubernetesPlugin", "--export-dir", str(cls.export),
            "--transform-dir", str(transform), "--plugin-dir", str(cls.work / "no-plugins"),
            *extra_flags,
        )
        cls.run_crane("apply", "--transform-dir", str(transform), "--output-dir", str(output))
        return index_documents(load_documents(output / "output.yaml"))

    @classmethod
    def apply_target(cls, transform, output):
        cls.run_crane(
            "apply", "50_ArgoTarget", "--transform-dir", str(transform),
            "--output-dir", str(output),
        )
        return index_documents(load_documents(output / "output.yaml"))

    def test_default_cleanup_preserves_custom_resource_specs_and_removes_status(self):
        app = self.default["Application", "local-app"]
        self.assertEqual(app["spec"], self.source["Application", "local-app"]["spec"])
        for doc in self.default.values():
            self.assertNotIn("status", doc)
            self.assertNotIn("uid", doc["metadata"])
            self.assertNotIn("resourceVersion", doc["metadata"])
        self.assertIn("operation", app)
        self.assertIn("finalizers", app["metadata"])

    def test_default_drops_owned_children_and_configuration(self):
        self.assertEqual(len(self.source), 13)
        self.assertEqual(len(self.default), 10)
        for key in [
            ("Application", "fleet-source-workloads"),
            ("ConfigMap", "argocd-rbac-cm"),
            ("Deployment", "platform-server"),
        ]:
            self.assertNotIn(key, self.default)
        self.assertIn(("ApplicationSet", "fleet"), self.default)
        self.assertNotIn("policy", self.default["ArgoCD", "platform"]["spec"]["rbac"])

    def test_retaining_owned_objects_leaves_source_owner_uids(self):
        self.assertEqual(len(self.owned), 13)
        child = self.owned["Application", "fleet-source-workloads"]
        self.assertEqual(
            child["metadata"]["ownerReferences"],
            self.source["Application", "fleet-source-workloads"]["metadata"]["ownerReferences"],
        )
        self.assertIn(("Deployment", "platform-server"), self.owned)

    def test_namespace_only_does_not_map_gitops_destinations_or_secret_payload(self):
        app = self.namespace_only["Application", "explicit-app"]
        self.assertEqual(app["metadata"]["namespace"], "gitops-target")
        self.assertEqual(app["spec"]["destination"], {
            "server": "https://api.source.example.test:6443", "namespace": "payments-source",
        })
        secret = self.namespace_only["Secret", "registered-workloads"]
        self.assertEqual(secret_values(secret)["name"], "source-workloads")

    def test_standalone_destinations_and_source_overlays(self):
        local = self.target["Application", "local-app"]["spec"]
        explicit = self.target["Application", "explicit-app"]["spec"]
        self.assertEqual(local["destination"], {
            "server": "https://kubernetes.default.svc", "namespace": "payments-target",
        })
        self.assertEqual(explicit["destination"], {
            "server": "https://api.target.example.test:6443", "namespace": "payments-target",
        })
        for spec in [local, explicit]:
            self.assertEqual(spec["source"]["path"], "payments/overlays/target")
            self.assertEqual(spec["source"]["targetRevision"], "migration-target")

    def test_named_destination_and_multisource_helm_values(self):
        spec = self.target["Application", "named-multi-app"]["spec"]
        self.assertEqual(spec["destination"], {
            "name": "target-workloads", "namespace": "payments-target",
        })
        self.assertEqual(spec["sources"][0]["helm"]["valueFiles"], [
            "$values/environments/target/values.yaml",
        ])
        self.assertEqual(spec["sources"][1]["targetRevision"], "migration-target")
        self.assertEqual(spec["sources"][0]["targetRevision"], "1.2.3")
        self.assertEqual(spec["sources"][1]["ref"], "values")

    def test_appset_generator_inputs_templates_and_overrides(self):
        fleet = self.target["ApplicationSet", "fleet"]["spec"]
        generator = fleet["generators"][0]
        self.assertEqual(generator["list"]["elements"], [{
            "cluster": "target-workloads", "namespace": "payments-target",
        }])
        self.assertEqual(generator["template"]["spec"]["destination"], {
            "name": "target-workloads", "namespace": "payments-target",
        })
        self.assertEqual(fleet["template"]["spec"]["destination"]["name"], "{{cluster}}")
        self.assertEqual(fleet["template"]["spec"]["source"]["path"], "payments/overlays/target")
        git = self.target["ApplicationSet", "git-fleet"]["spec"]
        self.assertEqual(git["generators"][0]["git"]["directories"], [{"path": "clusters/target/*"}])
        self.assertEqual(git["generators"][0]["git"]["revision"], "migration-target")
        self.assertEqual(git["template"]["spec"]["destination"], {
            "server": "https://api.target.example.test:6443", "namespace": "payments-target",
        })
        self.assertEqual(git["template"]["spec"]["source"]["path"], "{{path}}")

    def test_sync_is_paused_in_apps_and_all_fixture_appset_templates(self):
        for (kind, _), doc in self.target.items():
            if kind == "Application":
                self.assertNotIn("automated", doc["spec"].get("syncPolicy", {}))
            elif kind == "ApplicationSet":
                templates = [doc["spec"]["template"]] + [
                    generator["template"] for generator in doc["spec"]["generators"]
                    if "template" in generator
                ]
                for template in templates:
                    self.assertNotIn("automated", template["spec"].get("syncPolicy", {}))

    def test_operation_and_stale_tracking_removed_but_lifecycle_finalizer_preserved(self):
        app = self.target["Application", "local-app"]
        self.assertNotIn("operation", app)
        self.assertNotIn("argocd.argoproj.io/tracking-id", app["metadata"].get("annotations", {}))
        self.assertNotIn("argocd.argoproj.io/instance", app["metadata"]["labels"])
        self.assertEqual(app["metadata"]["labels"]["team"], "payments")
        self.assertEqual(app["metadata"]["finalizers"], ["resources-finalizer.argocd.argoproj.io"])

    def test_project_policies_allow_both_target_destinations(self):
        project = self.target["AppProject", "payments"]["spec"]
        self.assertEqual(project["sourceNamespaces"], ["team-apps-target"])
        self.assertEqual(project["destinations"], [
            {"server": "https://kubernetes.default.svc", "namespace": "payments-target"},
            {"server": "https://api.target.example.test:6443", "namespace": "payments-target"},
        ])
        self.assertIn("payments/team-apps-target/*", project["roles"][0]["policies"][0])
        self.assertEqual(project["sourceRepos"], self.source["AppProject", "payments"]["spec"]["sourceRepos"])

    def test_cluster_credentials_replaced_and_repository_credentials_preserved(self):
        secret = self.target["Secret", "registered-workloads"]
        values = secret_values(secret)
        self.assertNotIn("data", secret)
        self.assertEqual(values["name"], "target-workloads")
        self.assertEqual(values["server"], "https://api.target.example.test:6443")
        self.assertEqual(values["namespaces"], "payments-target")
        config = json.loads(values["config"])
        self.assertEqual(config["bearerToken"], "target-fixture-token-not-real")
        self.assertEqual(base64.b64decode(config["tlsClientConfig"]["caData"]), b"target-fixture-ca-not-real")
        self.assertFalse(config["tlsClientConfig"]["insecure"])
        self.assertEqual(secret["metadata"]["labels"]["environment"], "target")
        self.assertEqual(secret["metadata"]["labels"]["argocd.argoproj.io/secret-type"], "cluster")
        repo = self.target["Secret", "private-repo"]
        self.assertEqual(repo["data"], self.source["Secret", "private-repo"]["data"])
        self.assertEqual(repo["metadata"]["labels"]["argocd.argoproj.io/secret-type"], "repository")

    def test_operator_configuration_recovered_without_generated_resources(self):
        spec = self.target["ArgoCD", "platform"]["spec"]
        self.assertEqual(spec["sourceNamespaces"], ["team-apps-target"])
        self.assertEqual(spec["server"]["route"]["host"], "argocd.target.example.test")
        self.assertEqual(spec["rbac"]["policy"], self.source["ConfigMap", "argocd-rbac-cm"]["data"]["policy.csv"])
        self.assertEqual(spec["rbac"]["scopes"], "[groups]")
        self.assertEqual(spec["rbac"]["defaultPolicy"], "role:readonly")
        for doc in self.target.values():
            self.assertNotIn("ownerReferences", doc["metadata"])
        self.assertNotIn(("Deployment", "platform-server"), self.target)
        self.assertNotIn(("Application", "fleet-source-workloads"), self.target)

    def test_namespace_maps_and_cross_namespace_rbac(self):
        self.assertEqual(len(self.target), 13)
        for (kind, name), doc in self.target.items():
            if kind == "Namespace":
                continue
            expected = "payments-target" if kind == "RoleBinding" else "gitops-target"
            if kind == "Application" and name == "named-multi-app":
                expected = "team-apps-target"
            self.assertEqual(doc["metadata"]["namespace"], expected)
        binding = self.target["RoleBinding", "gitops-access"]
        self.assertEqual(binding["subjects"][0]["namespace"], "gitops-target")
        self.assertEqual(binding["subjects"][1]["namespace"], "shared-security")
        self.assertEqual(self.target["Namespace", "payments-target"]["metadata"]["labels"], {
            "argocd.argoproj.io/managed-by": "gitops-target",
        })

    def test_repeatable_output_and_immutable_inputs(self):
        self.assertEqual(self.target, self.replay)
        self.assertEqual(digest_tree(self.export), self.export_hash)
        self.assertEqual(digest_tree(ROOT / "fixtures"), self.fixture_hash)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crane", default="crane", help="Crane executable to test")
    parser.add_argument("--work-dir", type=Path, help="New directory for logs and generated manifests")
    OPTIONS = parser.parse_args()
    executable = shutil.which(OPTIONS.crane)
    if not executable:
        parser.error(f"Crane executable not found: {OPTIONS.crane}")
    OPTIONS.crane = str(Path(executable).resolve())
    if OPTIONS.work_dir:
        OPTIONS.work_dir = OPTIONS.work_dir.resolve()
        OPTIONS.work_dir.mkdir(parents=True, exist_ok=False)
    else:
        OPTIONS.work_dir = Path(tempfile.mkdtemp(prefix="crane-argocd-"))
    print(f"Crane: {OPTIONS.crane}", flush=True)
    print(f"Artifacts: {OPTIONS.work_dir}", flush=True)
    unittest.main(argv=[__file__], verbosity=2)
