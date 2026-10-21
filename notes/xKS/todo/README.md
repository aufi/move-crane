# xKS migration follow-ups

Record required changes, open design questions, and checks discovered during xKS migration runs here. Separate observed behavior from proposed changes and untested assumptions. Implementation belongs in the Crane ecosystem repositories.

| ID | Topic | Status |
| --- | --- | --- |
| [001](001-ciliumendpoint.md) | Exclude generated CiliumEndpoint state; assess default whiteout behavior and distinguish it from OpenShift Routes | Workaround verified; default behavior and regression checks pending |
| [002](002-aks-to-crc-transfer-prerequisites.md) | Restore CRC namespace admission and prepare an AKS-reachable transfer path | Resolved for this run by CRC recreation and indirect S3 transfer |
| [003](003-indirect-transfer-validation.md) | Indirect transfer metadata retry, PodSecurity warning, verification semantics, and target runtime checks | Content transfer and CRC application runtime verified; mover follow-ups pending |
