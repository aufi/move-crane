# Tanzu adoption evidence and development priorities

## Purpose

Assess which VMware Kubernetes source profiles should receive Crane development and validation effort for migration to OCP 4 or 5. This document supplements the [TKG, VKS, and VCF comparison](TANZU_VCF.md) and follows the scope and validation gates in the [xKS plan](README.md).

Research date: 2026-11-12. Public pages and their counts can change.

## Findings

No reliable public usage breakdown between standalone TKG, Supervisor-managed TKG Service/VKS, and TKGI was found in this research. We cannot identify the most common distribution or assign defensible market-share percentages to these profiles.

The available numerical estimates group products under broad Tanzu names and disagree substantially. They can identify possible accounts for further discovery, but cannot determine the development order between distributions.

The strongest actionable evidence concerns migration pressure:

- Broadcom identifies standalone TKG v2.5.4 as the final enterprise release and directs customers toward Supervisor and VKS.
- Broadcom documents that TKGI 1.2x is incompatible with VCF 9.1 and NSX 9.1. The same knowledge-base article states that TKGI end of support takes effect in October 2027.
- VKS is the continuing Supervisor-based service. That makes it a relevant source for ongoing compatibility, but does not establish that it has the largest installed base or the largest OpenShift migration demand.

For Crane, prioritize confirmed applications moving to OpenShift. Product popularity alone would not tell us how many customers intend to migrate.

## Public numerical evidence

These are source-reported values, not independently verified installation counts.

| Source | Reported figure | Population and date | What it supports | Main limitation |
| --- | --- | --- | --- | --- |
| [Enlyft TKG profile](https://enlyft.com/tech/products/vmware-tanzu-kubernetes-grid) | 3,608 companies; 0.86% of its Virtualization Management Software category | Page says data updated 2026-11-01 | A commercial database identifies companies associated with the TKG name | No TKGm/TKGs/VKS/TKGI split, production confirmation, cluster count, or migration intent |
| [6sense TKG profile](https://6sense.com/tech/cluster-management/tanzu-kubernetes-grid-market-share) | 197 current customers; estimated 0.19% of its Cluster Management category | Snapshot accessed 2026-11-12; page labels its data as 2026 | Another commercial database detects use of the TKG name | No architecture split; category includes overlapping technologies such as Kubernetes and Tanzu for Kubernetes Operations |
| [6sense VMware Tanzu profile](https://6sense.com/tech/containerization/vmware-tanzu-market-share) | 1,235 current customers; estimated 0.63% of its Containerization category | Snapshot accessed 2026-11-12; page labels its data as 2026 | Broad Tanzu account-discovery signal | Covers a product suite rather than a specific Kubernetes distribution; page body separately says over 1,224 companies |
| [Spectro Cloud 2024 State of Production Kubernetes](https://cdn.prod.website-files.com/64105dfa8da6a9f617932c6c/66c49db47d61e1419a8dc40a_Spectro%20Cloud%202024%20State%20of%20Production%20Kubernetes.pdf), pages 34 and 38 | 59% said Broadcom's VMware acquisition accelerated cloud-native adoption; 43% were investigating less costly software vendors | 416 production-Kubernetes respondents surveyed in April 2024 by Adience; 83% located in the USA | Historical evidence of infrastructure cost and migration pressure | Vendor-sponsored survey of Kubernetes users, not a Tanzu installed-base survey; neither figure measures Tanzu-to-OpenShift migration |

Do not add these company counts, average them, or treat them as lower and upper bounds of the real installed base. The datasets have different coverage, classifications, and possible overlap. A company can also operate several distributions.

The category percentages do not describe shares within Tanzu. In particular, neither 0.86% nor 0.19% tells us the share of standalone TKG versus Supervisor-managed clusters.

The 6sense TKG page also lists 1,108 domains for Tanzu for Kubernetes Operations. That is a broader offering, not another mutually exclusive distribution. It cannot be used as a proxy for Supervisor/VKS adoption.

## Evidence by source profile

| Profile | Verified public evidence | Interpretation for Crane | What remains unknown |
| --- | --- | --- | --- |
| Standalone TKG on vSphere | [TKG release notes](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/mgmt-release-notes.html) identify v2.5.4, released 2025-06-25, as the final enterprise release. A [Capstone case study](https://capstone-s.com/vmware-case-study-tanzu-kubernetes-grid/) published 2025-01-16 explicitly describes a TKGm 1.6 deployment for an unnamed energy company | A documented installed source architecture with a vendor-directed transition. Suitable for an initial legacy-source migration profile | Installed-base size, current versions, number of applications leaving, and preferred destination |
| Legacy Supervisor-managed TKG Service and current VKS | Broadcom describes [VKS as the successor to TKG Service](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/migrate-tkgs-migration.html) and maintains [current VKS release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-release-notes.html) | Important continuing source family. Retain separate tests for selected legacy and current releases | Customer and cluster counts, release distribution, and how many VCF customers actually run VKS applications |
| TKGI, formerly Enterprise PKS | Broadcom [KB 446224](https://knowledge.broadcom.com/external/article/446224/incompatibility-between-tanzu-kubernetes.html) documents incompatibility with VCF/NSX 9.1, October 2027 end of support, and the need to migrate applications before infrastructure upgrades. A [2024 VMware post](https://blogs.vmware.com/tanzu/tap-on-tkgi/) describes enterprise use for critical workloads without a count | A distinct legacy source with migration pressure. Give it an early demand assessment rather than assuming that a legacy product is unimportant | Installed-base size, affected customer schedules, actual networking/storage profiles, and OpenShift destination commitments |
| Direct Supervisor/vSphere Pod workloads | The [architecture comparison](TANZU_VCF.md#migration-boundary) distinguishes these from workload-cluster applications | Keep a separate scope decision. Public evidence gathered here does not justify prioritizing it over workload clusters | Adoption and migration demand |

The Capstone case study is one partner-reported deployment, not a prevalence estimate. Its publication date does not prove that the customer still runs TKGm 1.6 in November 2026. The utility's more than four million customers are customers of the utility, not Tanzu customers.

Final release, end of availability, and end of support are different events. Do not infer a standalone TKG end-of-support date from the final-release announcement. Check the [Broadcom lifecycle matrix](https://support.broadcom.com/group/ecx/productlifecycle) for each source release. The TKGI October 2027 statement above is attributed to KB 446224; confirm applicable lifecycle and contract details during customer discovery.

## Recommended development focus

This is a provisional engineering order based on migration pressure and reusable work. It is not a ranking of distribution popularity. It applies within the Tanzu workstream and does not change the README's AKS-first provider sequence.

| Priority | Work | Reason and decision gate |
| --- | --- | --- |
| First | Shared VMware workload-cluster discovery and migration rules; validate standalone TKG on vSphere as the default first source profile | TKG has a documented final enterprise release and an explicit migration path. Start with a real customer profile and available test environment; change the first profile if confirmed demand favors another distribution |
| Early parallel discovery | Assess TKGI opportunities and obtain representative sanitized fixtures and platform access | Its documented infrastructure incompatibility and support deadline can create nearer-term migration projects. Promote TKGI to the first validation profile if committed OpenShift migrations outweigh TKGm opportunities |
| Next validation profile | Supervisor-managed workload clusters, with selected legacy TKG Service and current VKS releases validated independently | Covers a different storage/access path and the continuing VMware Kubernetes service. Reuse common application rules, but validate pvCSI and Supervisor-derived storage policies separately |
| Demand-led expansion | Additional CNI, ingress, RWX, private-network, OS, and release combinations | Extend the matrix according to customer dependencies and reproduced failures rather than product branding |
| Separate scope decision | Direct Supervisor/vSphere Pod workloads | Different execution context; no measured prevalence or confirmed project was established by this research |

Do not start separate complete plugins for TKGm, VKS, and TKGI. Share handlers for discovered dependencies, while preserving independently validated source profiles. Implementation belongs in [crane-plugin-xks-to-ocp](https://github.com/migtools/crane-plugin-xks-to-ocp), Crane, or crane-lib as appropriate.

The first useful engineering capabilities are:

- Identify the actual workload-cluster context and record the source profile without requiring a management-plane connection for every application export.
- Inventory application APIs and controller dependencies, including Contour/Avi exposure and Antrea/Calico policies where installed. TKGI discovery must inspect its actual NSX/NCP or other networking configuration.
- Map standalone PVCs and StatefulSet claim templates to target storage capabilities and verify filesystem data transfer.
- Distinguish application intent from generated state and cluster-lifecycle objects. Report missing controllers and external integrations as owner-managed prerequisites.
- Verify direct transfer and the required indirect fallback on each selected source and exact OCP target profile.

These are proposed validation areas, not evidence that a specific integration is the most frequently deployed.

## Gather the missing distribution statistics

The next evidence should come from the organizations that may use Crane. Use a short, structured intake with account teams, migration partners, and platform owners. A convenience sample of the first 10 to 20 organizations can guide pilot selection, but must not be presented as global market share.

Collect one record per distinct source profile within each organization:

| Field | Why it matters |
| --- | --- |
| Organization identifier and evidence date | Deduplicate reports and identify stale information |
| Verified product, version, and cluster type | Separate TKGm, TKG Service/VKS, TKGI, and direct Supervisor workloads |
| Production workload-cluster count | Measure deployment scale without counting management clusters as application clusters |
| Applications/namespaces in migration scope | Estimate actual Crane migration work; a cluster count alone is insufficient |
| Stateful applications, PVC count, approximate data volume, and access modes | Estimate transfer requirements and validation effort |
| CNI, policy APIs, ingress/load balancer, CSI, registry, and identity dependencies | Identify reusable transformation and prerequisite work |
| Destination, decision status, migration window, and source support constraints | Separate committed OpenShift migration demand from VMware upgrades or uncommitted evaluations |
| Access to a pilot environment and sanitized export fixtures | Determine whether the profile can be verified and regression-tested |

Publish at least these separate measures:

1. Organizations using each profile, allowing an organization to appear in several profiles.
2. Production workload clusters per profile, excluding management clusters.
3. Applications committed to OCP migration per profile and migration window.
4. Stateful application/PVC volume and recurring dependency combinations.

Always show sample size, collection period, missing/unknown classifications, and whether numbers are verified or self-reported. Do not normalize overlapping organization counts into a pie chart of mutually exclusive shares.

Choose the first source using confirmed migration volume and deadline, then consider the reusable dependencies and effort required to test it. Revisit the provisional order after the initial intake and first pilot. Do not wait for a global market-share estimate to begin shared discovery and fixture collection.

## Research coverage and confidence

Research covered public adoption and market-share searches, 6sense and Enlyft product profiles, VMware/Broadcom product documentation and lifecycle statements, a partner case study, and the full Spectro Cloud 2024 report. The [CNCF 2023 survey](https://www.cncf.io/reports/cncf-annual-survey-2023/) and [2024 survey landing page](https://www.cncf.io/reports/cncf-annual-survey-2024/) were also reviewed; the reviewed material did not provide the required Tanzu architecture split. The linked CNCF 2024 PDF and raw survey datasets were not analyzed.

Some search endpoints returned bot challenges or unusable results, and some pages were inaccessible. This is a bounded public-source search, not proof that no private analyst or vendor dataset exists.

| Conclusion | Confidence |
| --- | --- |
| Retrieved company-count estimates do not establish the distribution split | High, based on the published categories and missing architecture fields |
| Standalone TKG has a final enterprise release and TKGI has documented VCF/NSX 9.1 incompatibility | High, based on Broadcom documentation |
| Which Tanzu distribution is most common | Unknown |
| Which distribution has the largest OpenShift migration opportunity | Unknown until customer intake |
| Start with shared workload-cluster capabilities and a demand-adjustable TKGm pilot | Provisional engineering recommendation, not a statistical result |
