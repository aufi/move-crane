# KubeVirt cleanup plugin

Test-only Crane binary plugin. It removes controller-owned metadata and status
from `kubevirt.io/v1` VirtualMachines and whiteouts VirtualMachineInstances.

Build and run the tests:

```bash
go test ./...
go build -o KubeVirtCleanupPlugin .
```

Install the binary into a dedicated test plugin directory and add a transform
stage named `20_KubeVirtCleanupPlugin`. Do not install it as a production
plugin. It does not yet discover VM storage or network dependencies.

The plugin was verified against `../migration/export`. Crane created
`10_KubeVirtCleanupPlugin`, then `15_KubernetesPlugin`; the rendered output
contained the three VirtualMachines without KubeVirt finalizers.
