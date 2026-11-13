# Fullsend assignment for Crane E2E test development

## Status and objective

Agreed direction, November 13, 2026. Implementation and live validation are
pending.

Use Fullsend initially to implement and improve Crane E2E tests. Give the agent
feedback from real Kubernetes executions, first through existing PR CI and then
through focused tests inside the Fullsend run. Use internal OpenShift or CRC
environments for scenarios that require OpenShift behavior.

Deliver this work in three stages:

1. Implement tests and iterate through existing PR CI.
2. Run focused E2E tests against runner-local minikube between Fullsend iterations.
3. Add an internal execution path for OpenShift and CRC.

The initial target is `aufi/crane-fullsend-pilot`. Implementation belongs in the
pilot repository and its Fullsend configuration. This workspace holds the
assignment and evaluation results. Moving the setup or resulting tests upstream
requires a separate decision.

Use the [EnMaaS plan](FULLSEND_ENMAAS_PLAN.md) and
[November 13 update review](FULLSEND_UPDATES_2026-11-13.md) for inference and
version prerequisites. The upgrade candidate is Fullsend and agents v0.55.0,
with pi preferred subject to EnMaaS validation. Record the exact versions,
harness revisions, and image digests used by the experiment.

## Existing foundation

The upstream Crane CI reviewed for this assignment already provides:

- Source and target minikube profiles, `src` and `tgt`, on a common Docker network.
- Non-admin contexts, normally `src-dev` and `tgt-dev`.
- A Ginkgo/Gomega E2E framework using Crane, `kubectl`, `client-go`, and
  `k8sdeploy`.
- Focused execution of touched test files for test-only PRs, and broader tier0
  and tier1 execution for implementation or shared-framework changes.

Before implementation, compare the pilot checkout with that upstream setup.
Record the source revision and identify any missing workflows, scripts, or
framework changes. Reuse the existing test runner and cluster setup rather than
creating a second E2E framework.

## Stage 1: E2E development through PR CI

### Work to deliver

1. Select one small Kubernetes scenario with explicit expected behavior and
   assertions. Prefer a scenario that runs in focused CI without external
   storage credentials or OpenShift-only APIs.
2. Provide the code agent with a task describing the scenario, test location,
   reusable framework helpers, expected cleanup, and acceptance criteria.
3. Have Fullsend implement the test, run available build and unit checks, and
   publish a PR in the pilot repository.
4. Run the existing PR E2E workflow against that PR. Verify that bot-created
   PRs and subsequent bot pushes actually trigger the expected checks.
5. When E2E fails, invoke `/fs-fix` after CI completes. The fix agent must inspect
   project CI logs and available artifacts, diagnose the failure, and correct
   changes within the task's scope.
6. Keep the existing required PR checks as the final merge gate.

Initial fix dispatch is manual. A failed CI check does not, by itself, trigger
the default Fullsend fix agent. Automatic CI-to-fix orchestration is a later
extension, not a prerequisite for this stage.

### Acceptance criteria

- A Fullsend-authored PR adds or improves one E2E scenario using the existing
  framework, with assertions that exercise the requested behavior.
- The applicable test executes on real minikube clusters and passes. A skipped
  test, empty test selection, or successful compilation alone is not a pass.
- A controlled failing run demonstrates that the fix agent can obtain useful
  CI evidence and produce a correction verified by a subsequent CI run.
- Where the task covers a regression, demonstrate that the test detects the
  known faulty behavior when a reproducible baseline is available. Otherwise,
  document a meaningful controlled failure of the behavior being asserted.
- Changes preserve the intended assertions and test coverage. Do not make the
  check green by skipping the test or removing the behavior under test.
- Record the issue, PR, tested commits, CI runs, manual interventions, and result.

## Stage 2: Runner-local minikube and Fullsend validation feedback

### Execution model

```text
GitHub Actions job
  Prepare minikube src/tgt and test dependencies
  Run Fullsend
    Agent edits and commits tests in the OpenShell sandbox
    Fullsend extracts the candidate repository to the runner
    Host validation runs the selected E2E against minikube
    Failure diagnostics feed the next agent iteration
    A validated candidate is published as a PR or PR update
  Collect results and clean up

PR CI independently verifies the published change
```

Cluster provisioning and E2E execution run on the Actions runner. The agent
sandbox does not need a kubeconfig, direct Kubernetes API access, a Docker
socket, or permission to provision clusters in this stage.

### Work to deliver

1. Prepare the clusters in the same job as Fullsend, using a repository-owned
   workflow or a trusted host pre-script. A cluster created in a separate
   GitHub-hosted job is not automatically available to the agent job.
2. Reuse Crane's minikube preparation, contexts, and connectivity checks.
   Prepare Go, Ginkgo, Python dependencies, `k8sdeploy`, and the plugins needed
   by the selected scenario on the runner.
3. Derive both code and fix harnesses from pinned fleet harnesses. Add a host
   validation wrapper using `validation_loop.script`, preserving the shipped
   structured-output and pre-commit checks.
4. Run the selected E2E from the extracted candidate at `TARGET_REPO_DIR`.
   Rebuild Crane and any affected local plugins from that candidate. Do not
   accidentally execute the initial checkout or a stale binary.
5. Use `feedback_mode: append` to return a concise failure diagnosis to the
   next iteration. Include the test identity, failing assertion, and relevant
   command or cluster evidence. Retain full test reports separately.
6. Provision once per job and clean up scenario resources between attempts.
   Keep repeated execution independent of leftovers from a previous attempt.
7. Start with at most two agent attempts per run and a focused test selection.
   Set explicit setup, test, agent, and job time budgets based on the initial
   measurement. Distinguish a test assertion failure from cluster setup,
   registry, or other infrastructure failures.
8. Ensure the final published candidate has a passing E2E result for its exact
   tested content. Account for Fullsend's final validation sweep and any
   post-script modifications; do not rely on an earlier attempt's success for
   different content. PR CI remains authoritative for the published commit.
9. Collect test reports and diagnostics on failure and perform cleanup when the
   job ends. Record the resource requirements of both clusters and Fullsend.

Custom workflow and harness infrastructure is prepared separately from the
agent's E2E task. The standard coder identity cannot publish changes to GitHub
workflow files.

### Acceptance criteria

- One Fullsend job provisions the required minikube clusters and executes a
  focused E2E from the agent's candidate checkout.
- A failing assertion reaches the agent through validation feedback, and a
  subsequent iteration runs the corrected candidate against the live clusters.
- The selected tests demonstrably executed. Reports identify the candidate
  commit and any worktree changes included in the test run.
- Repeating the scenario does not depend on resources left by the first attempt.
- A setup or infrastructure failure is reported as such, rather than recorded
  as a passing test or prompting unrelated test changes.
- The published PR passes the applicable existing PR CI checks independently.
- The experiment records setup time, test time, agent time, token usage,
  available cost accounting, runner size, retries, and manual intervention.

## Stage 3: Internal OpenShift and CRC execution

### Work to deliver

1. Add an internal self-hosted runner path with access to a test OpenShift
   cluster or a prepared CRC installation. Reuse the host validation wrapper
   and test framework from stage 2.
2. Select an OpenShift-specific scenario and explicitly document the required
   APIs, operators, storage, and permissions. Verify real OpenShift behavior;
   Kubernetes fixtures alone do not establish OCP compatibility.
3. Supply source, target, and non-admin contexts through runner configuration.
   State whether the scenario requires two clusters or can use one cluster
   with separate namespaces. Do not substitute a single-cluster run for a
   cross-cluster acceptance criterion.
4. Allocate resources per run. Namespace isolation is sufficient only for
   scenarios without conflicting cluster-scoped changes. For CRDs, ClusterRoles,
   operators, or other shared state, use a dedicated environment or serialize
   execution and define cleanup.
5. For CRC, use a host with the required virtualization, resources, and pull
   secret already configured. Starting CRC on a standard GitHub-hosted runner
   is not part of this stage.

### Acceptance criteria

- The same Fullsend feedback cycle executes an OCP-specific test on a real
  OpenShift or CRC environment.
- Reports record the platform version, topology, contexts, selected scenario,
  tested candidate, and actual execution result.
- Concurrent or repeated runs do not reuse conflicting test resources.
- Cleanup covers the resources created by the scenario and reports failures.
- Kubernetes and OpenShift results remain distinguishable in the evaluation.

## Deferred extensions

- **Automatic CI-to-fix dispatch.** Add only after stage 1 proves useful.
  Match failures to the current PR head, wait for relevant checks to finish,
  avoid duplicate dispatch, and impose a retry cap. Use a repository-owned
  dispatch path supported by Fullsend authorization, rather than assuming a
  bot-authored `/fs-fix` comment will be accepted.
- **Direct cluster access from the sandbox.** Add if host validation is too
  slow or the agent needs interactive inspection. This requires a suitable
  image, portable kubeconfig, reachable API endpoints, and OpenShell network
  policies. Verify client-certificate TLS, `client-go`, exec, port-forward,
  and scenario-specific data paths. Runner-local loopback addresses are not
  reachable as the runner from inside the sandbox.

## Evaluation record and completion

For each stage, add a dated result in this directory linking the configuration
PR and representative agent and CI runs. Record the task, environment, exact
candidate, test selection, outcome, diagnostics, resource consumption, and
human corrections. Identify which steps are proven by live execution.

Proceed from stage 1 to stage 2 after demonstrating a useful CI-driven test
correction. Add stage 3 when an OpenShift-specific task and an internal runner
are available. Success means the agent produces a meaningful test that runs
and detects the intended behavior, with a reproducible correction cycle.

## References

- [Crane E2E framework](https://github.com/migtools/crane/blob/main/e2e-tests/README.md)
- [Crane PR E2E selection and gate](https://github.com/migtools/crane/blob/main/.github/workflows/e2e-pr-tester.yaml)
- [Crane minikube preparation action](https://github.com/migtools/crane/blob/main/.github/actions/setup-minikube-clusters/action.yml)
- [Crane minikube setup script](https://github.com/migtools/crane/blob/main/hack/setup-minikube-same-network.sh)
- [Crane E2E execution action](https://github.com/migtools/crane/blob/main/.github/actions/run-crane-e2e-tier/action.yml)
- [Fullsend code harness v0.55.0](https://github.com/fullsend-ai/agents/blob/v0.55.0/harness/code.yaml)
- [Fullsend fix agent and CI inspection](https://github.com/fullsend-ai/agents/blob/v0.55.0/docs/fix.md)
- [Harness customization](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/customizing-agents.md)
- [Host scripts and validation feedback](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/bring-your-own-agent.md)
- [Fullsend run lifecycle](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/cli/run.md)
- [Follow-up workflows](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/chaining-follow-up-workflows.md)
- [OpenShell v0.1.4 network rules](https://github.com/NVIDIA/OpenShell/blob/v0.1.4/docs/how-it-works/policies/network-rules.mdx)
