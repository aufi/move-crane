# Research notes on k8s workload migrations

## Index

- **[migration_general_steps.md](./migration_general_steps.md)** - General steps for application migration, backup & restore from an app-centric, namespace admin perspective
- **[personas.md](./personas.md)** - User personas related to Kubernetes migrations, including platform engineers, app developers, and their tool use-cases
- **[k8s_migrate_tools_and_needs.md](./k8s_migrate_tools_and_needs.md)** - Comparison of migration tools including Konveyor Crane, focused on application migration from an app-owner perspective
- **[k8s_migrate_tools_usage.md](./k8s_migrate_tools_usage.md)** - Practical usage examples showing minimal commands for migrating stateful applications with various tools
- **[kubectl_krew_overview.md](./kubectl_krew_overview.md)** - Overview of the kubectl and Krew plugin ecosystem, categorized by functionality with representative plugins

## Alternative CLI tools

Here is a **compact reference table** of **CLI-capable Kubernetes application migration / backup tools**, including **homepages and short, accurate descriptions**.

---

## Kubernetes Migration & Backup CLI Tools

| Tool name                       | Homepage                                                                                                                       | Short description                                                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| **Konveyor Crane**              | [https://github.com/migtools/crane](https://github.com/migtools/crane))                                                           | CLI-first tool to export, transform, and migrate Kubernetes applications (manifests + optional data) between clusters.     |
| **Velero**                      | [https://velero.io](https://velero.io)                                                                                         | Open-source CLI and controller for Kubernetes backup, restore, and disaster recovery, including namespace-level migration. |
| **Kubectl (DIY)**               | [https://kubernetes.io/docs/reference/kubectl/](https://kubernetes.io/docs/reference/kubectl/)                                 | Native Kubernetes CLI used for manual export/import of manifests and ad-hoc data migration.                                |
| **Kasten K10**                  | [https://www.kasten.io](https://www.kasten.io)                                                                                 | Enterprise backup and application mobility platform with CLI-driven installation and API/CRD-based workflows.              |
| **Portworx Stork (`storkctl`)** | [https://docs.portworx.com](https://docs.portworx.com)                                                                         | Storage-centric migration and DR tool for Kubernetes workloads using Portworx volumes.                                     |
| **CloudCasa**                   | [https://cloudcasa.io](https://cloudcasa.io)                                                                                   | SaaS-based Kubernetes backup and migration tool with CLI/API support for automation.                                       |
| **Restic**                      | [https://restic.net](https://restic.net)                                                                                       | Fast, secure CLI backup tool often used by Velero for file-level PV backups.                                               |
| **Database-native CLIs**        | [https://www.postgresql.org/docs/current/app-pgdump.html](https://www.postgresql.org/docs/current/app-pgdump.html)             | DB-specific CLIs (pg_dump, mysqldump) for consistent logical backups of stateful apps.                                     |
| **Rsync**                       | [https://rsync.samba.org](https://rsync.samba.org)                                                                             | Low-level CLI tool for copying persistent volume data between clusters or pods.                                            |
| **CSI Snapshot tooling**        | [https://kubernetes.io/docs/concepts/storage/volume-snapshots/](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) | Kubernetes snapshot CRDs and controllers enabling storage-level backups via kubectl.                                       |

---

### Notes

* Only **Crane** is truly *migration-first* and *app-centric*.
* **Velero** and **K10** are *backup-first* tools commonly reused for migration.
* **kubectl + DB-native tools** remain the lowest common denominator.
* Storage-specific tools (Stork, CSI) trade portability for speed.
