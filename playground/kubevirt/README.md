# KubeVirt migration test environment

This playground prepares a local Minikube source cluster with KubeVirt and test
VirtualMachine resources for a later Crane migration test. It does not run
Crane yet.

The setup uses KubeVirt software emulation, so it works without `/dev/kvm`.
Emulation is slower than hardware virtualization but is sufficient for
exporting, transforming, and applying KubeVirt resources.

## Prerequisites

- `minikube`
- `kubectl`
- `curl`
- A Docker-compatible Minikube driver. Override it with `MINIKUBE_DRIVER` if
  needed.
- At least 4 CPUs and 8 GiB RAM available to Minikube.

## Create the source environment

```bash
./scripts/01-setup-minikube.sh
./scripts/02-deploy-test-vms.sh
./scripts/03-verify-test-vms.sh
```

The scripts use the `kubevirt-source` Minikube profile. Override it when
required:

```bash
MINIKUBE_PROFILE=my-source ./scripts/01-setup-minikube.sh
MINIKUBE_PROFILE=my-source ./scripts/02-deploy-test-vms.sh
MINIKUBE_PROFILE=my-source ./scripts/03-verify-test-vms.sh
```

The test manifest uses the `crane-kubevirt` namespace.

To use an already running Minikube profile, pass its name and driver. For the
local `kvm2` profile used in this workspace:

```bash
MINIKUBE_PROFILE=minikube MINIKUBE_DRIVER=kvm2 ./scripts/01-setup-minikube.sh
MINIKUBE_PROFILE=minikube ./scripts/02-deploy-test-vms.sh
MINIKUBE_PROFILE=minikube ./scripts/03-verify-test-vms.sh
```

`01-setup-minikube.sh` resolves the current KubeVirt stable release unless
`KUBEVIRT_VERSION` is set. Record the resolved version with the migration test
results. Use an explicit version to repeat a test:

```bash
KUBEVIRT_VERSION=v1.6.3 ./scripts/01-setup-minikube.sh
```

## Test resources

`manifests/test-vms.yaml` creates:

- `web-vm`, a running VM with a container disk.
- `configured-vm`, a running VM with cloud-init data and application labels.
- `stopped-vm`, a halted VM. Its stopped state checks whether Crane preserves
  `spec.runStrategy`.

All VMs use the public Cirros container disk. The scenario has no persistent
root disks or pod network interface. `configured-vm` has a `configured-data`
PVC used to test a separate data transfer.

## Crane migration flow

```bash
MINIKUBE_PROFILE=minikube ./scripts/02-deploy-test-vms.sh
SOURCE_CONTEXT=minikube ./scripts/04-crane-render.sh
./scripts/05-audit-rendered-output.sh

# Enable target ingress, then use a DNS name that resolves to its node IP.
minikube addons enable ingress --profile kubevirt-target
SUBDOMAIN="$(minikube ip --profile kubevirt-target).nip.io" \
  SOURCE_CONTEXT=minikube TARGET_CONTEXT=kubevirt-target ./scripts/07-transfer-pvc.sh

TARGET_CONTEXT=kubevirt-target ./scripts/06-apply-target.sh
```

`transfer-pvc` copies PVC data separately from the rendered resource manifests.
It needs a reachable NGINX ingress endpoint on the target and both Minikube
contexts in the active kubeconfig. The script stops `configured-vm` first so its
ReadWriteOnce disk is not copied while attached.

## Inspect and remove

```bash
kubectl --context kubevirt-source -n crane-kubevirt get vm,vmi
minikube delete --profile kubevirt-source
```

Removing the Minikube profile deletes the local cluster and all test data.
