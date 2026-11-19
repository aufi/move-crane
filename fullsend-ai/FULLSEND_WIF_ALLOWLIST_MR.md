# ITPC WIF allowlist merge request draft

Status: published after user approval as
[ITPC WIF inventory MR !9](https://gitlab.cee.redhat.com/itpc/gcp/inventories/workload-identity-federation/-/merge_requests/9).
The user created the fork in the browser after API fork creation was denied.
The branch was pushed through SSH, and GitLab push options created the MR.
The remote diff was verified to contain only the two approved additions.
The MR was merged as `016ebecaf0904062bfc62ea053a58edc9df4d588`.
The main-branch pipeline
[19503674](https://gitlab.cee.redhat.com/itpc/gcp/inventories/workload-identity-federation/-/pipelines/19503674)
passed. This confirms the inventory pipeline, not completion of its externally
triggered AAP deployment or a successful GitHub OIDC exchange.

## Post-merge checks

- Direct inspection of the central `github-com` provider was denied because the
  current GCP identity lacks `iam.workloadIdentityPoolProviders.get` in the ITPC
  utility project. A GitHub Actions token exchange can verify the consumer path.
- On November 19, the repo-scoped `roles/aiplatform.user` binding for
  `attribute.repository/migtools/crane` was added to `mta-ops-fs-agents` and
  verified by reading back the project IAM policy.
- `migtools/crane` has no Fullsend shim among its current workflow files. The
  current GitHub identity reports maintain access, not repository admin access.
- The old personal pilot `aufi/crane-fullsend-pilot` is outside this allowlist.
  A pilot must run under an approved owner or the initial manual WIF check can
  run directly in `migtools/crane`.

### Live WIF validation on November 19

[Crane PR #1154](https://github.com/migtools/crane/pull/1154) added the manual
smoke-test workflow and was merged as `bff861f66341b166bb9082164d7d225fc7d40d54`.
The repository variables select `mta-ops-fs-agents` and the central provider
`projects/21066242673/locations/global/workloadIdentityPools/itpc-identity-pool/providers/github-com`.

- [Authentication-only run 44552426660](https://github.com/migtools/crane/actions/runs/44552426660)
  passed the GitHub OIDC to GCP STS exchange.
- Inference initially returned HTTP 403 for missing
  `aiplatform.endpoints.predict`.
- After adding the repo-scoped binding and allowing IAM propagation,
  [run 44553417357](https://github.com/migtools/crane/actions/runs/44553417357)
  passed the WIF exchange and reached Vertex, which returned HTTP 404 for
  `claude-sonnet-4-6` in `global`: model not found or project access unavailable.
  A direct request with the developer's GCP identity returned the same 404.

After the user enabled `claude-sonnet-5-5` in Model Garden,
[run 44555023553](https://github.com/migtools/crane/actions/runs/44555023553)
passed both the WIF exchange and model inference in `global`. The response
identified `claude-sonnet-5-5` and reported 15 input tokens and 5 output tokens.
This verifies the GitHub Actions to central ITPC WIF to Vertex path for
`migtools/crane` and `mta-ops-fs-agents`. Fullsend runtime integration and
long-running credential refresh have not yet been verified.

## Target and proposed change

- Target project: `itpc/gcp/inventories/workload-identity-federation` on
  `gitlab.cee.redhat.com`.
- Target branch: `main`.
- Reviewed base commit: `45150e3b948523151eed42ff1ed01715daeb2dee`.
- Source branch: `add-fullsend-wif-owners` in `maufart/workload-identity-federation`.
- Title: `Add migtools and konveyor to allowed GitHub organizations for WIF`.
- File: `inventory/group_vars/wif_project/github.yaml`.

```diff
   - hermeto-fullsend
   - konflux-ci
+  - konveyor
   - manish-jangra
+  - migtools
   - openshift
```

The requested organizations are `migtools` and `konveyor`. The personal GitHub
owner `aufi` is excluded from this request.

## Proposed MR description

### Purpose

Add `migtools` and `konveyor` to the GitHub organization allowlist for the centrally
managed ITPC Workload Identity Federation provider.

This supports keyless access to Claude models on Vertex AI from Fullsend
GitHub Actions jobs in the `migtools` and `konveyor` organizations, including
`migtools/crane`.

The target GCP project is `mta-ops-fs-agents`.

### Scope

The existing provider checks `assertion.repository_owner`, so this change
allows both organizations through the provider's authentication condition.
It does not itself grant access to any GCP project.

Access to the target project will be configured separately using
`roles/aiplatform.user` bindings scoped to selected repositories via
`attribute.repository`. No owner-wide project IAM binding is requested.

### Validation

- YAML parsing and exact list comparison confirm that only `migtools` and
  `konveyor` are added, with no existing entries removed or reordered.
- Both entries occur exactly once, and the owner list has no duplicates.
- `git diff --check` passes.

Deployment and end-to-end GitHub OIDC exchange remain to be verified after
the inventory change is merged and deployed.

## Local preparation

The inventory checkout is `/tmp/opencode/fullsend-wif-inventory`.
The standalone MR description is `/tmp/opencode/fullsend-wif-mr-description.md`.
Local branch: `add-fullsend-wif-owners`.
Local commit: `f089255`, `Add migtools and konveyor to allowed GitHub organizations for WIF`.
The upstream base and open MRs were rechecked before publication. The fork's
relationship to the ITPC project and the published MR's target were verified.
The MR description contains the proposed text below as a single paragraph
because GitLab push options do not support multiline values.

The repository's CI includes YAML and Ansible lint jobs. Those tools were not
available locally; the checks above used Python with PyYAML and Git.
