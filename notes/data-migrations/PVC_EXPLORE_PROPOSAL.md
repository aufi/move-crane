# PVC Transfer Explore - Discovery & Command Generator

**Date:** 2026-07-03  
**Status:** Proposal  
**Purpose:** Add `crane transfer-pvc explore` command to discover PVCs from crane export and generate ready-to-use transfer commands

---

## Executive Summary

Add intelligent PVC discovery that analyzes `crane export` output directory and generates ready-to-use `crane transfer-pvc` commands.

**Problem:** After `crane export`, users must manually:
1. Find which PVCs need transfer
2. Understand PVC dependencies (which workloads use them)
3. Figure out correct transfer commands
4. Handle StatefulSet PVC naming patterns
5. Map storage classes between clusters

**Solution:** `crane transfer-pvc explore` automates discovery and generates copy-paste-ready commands.

---

## Use Case Example

### Before (Manual Discovery)

```bash
# User workflow today:
crane export --context=source --namespace=myapp --export-dir=myapp/

# Now what? User must:
ls myapp/persistentvolumeclaim_*.yaml  # Find PVCs
cat myapp/deployment_*.yaml           # See which workloads use them
# ... manually create transfer commands
```

### After (Automated Discovery)

```bash
# New workflow:
crane export --context=source --namespace=myapp --export-dir=myapp/

crane transfer-pvc explore --export-dir=myapp/ --target-context=dest

# Output:
# ================================================================================
# PVC Transfer Plan for namespace: myapp
# Source cluster: (from export metadata)
# Target cluster: dest
# ================================================================================
#
# Found 4 PVCs to transfer:
#
# 1. postgres-data (50Gi, storageClass: gp2)
#    Used by: Deployment/postgres
#    Transfer command:
#
#    crane transfer-pvc \
#      --source-context=source \
#      --destination-context=dest \
#      --pvc-name=postgres-data \
#      --pvc-namespace=myapp \
#      --verify
#
# 2. redis-cache (10Gi, storageClass: gp2)
#    Used by: Deployment/redis
#    Note: Consider if cache needs transfer (can be rebuilt)
#
# 3-5. data-kafka-{0,1,2} (100Gi each, storageClass: gp2)
#    Used by: StatefulSet/kafka-cluster
#    Transfer commands (run in parallel):
#
#    for i in 0 1 2; do
#      crane transfer-pvc \
#        --source-context=source \
#        --destination-context=dest \
#        --pvc-name=data-kafka-cluster-$i \
#        --pvc-namespace=myapp &
#    done
#    wait
#
# ================================================================================
# Storage Class Mapping Recommendations:
# ================================================================================
#
# Source storage class 'gp2' (AWS EBS) may need mapping to target cluster.
# Suggested target storage classes:
#   - GCP: standard-rwo (Google Persistent Disk)
#   - Azure: managed-premium (Azure Disk)
#   - On-prem: Consider available storage classes
#
# To apply mapping, use:
#   --storage-class-map=gp2:standard-rwo
#
# ================================================================================
# Recommended Migration Order:
# ================================================================================
#
# 1. Transfer stateless workloads first (already done via crane apply)
# 2. Scale down stateful workloads:
#      kubectl scale deployment postgres --replicas=0 -n myapp --context=source
#      kubectl scale statefulset kafka-cluster --replicas=0 -n myapp --context=source
# 3. Run transfer commands above
# 4. Apply stateful workloads to target:
#      crane apply --export-dir=myapp/ --context=dest --include-resources=deployment,statefulset
#
# Save these commands to a file:
#   crane transfer-pvc explore --export-dir=myapp/ --output=transfer-plan.sh
```

---

## CLI Interface

### Basic Usage

```bash
# Analyze export directory
crane transfer-pvc explore --export-dir=<path>

# Specify target cluster context
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=dest-cluster

# Override source context (if different from export metadata)
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --source-context=prod-cluster \
  --target-context=dr-cluster

# Generate executable script
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=dest \
  --output=transfer-plan.sh \
  --format=script

# Generate migration instructions file (like crane transform)
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --output=pvc-migration.yaml \
  --format=instructions

# Output as JSON (for automation)
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --format=json > transfer-plan.json

# Just console output (default)
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=dest

# Filter by workload type
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --include-workloads=statefulset  # Only StatefulSets
```

---

## Flags

| Flag | Type | Description | Default |
|------|------|-------------|---------|
| `--export-dir` | string | Path to crane export directory (required) | - |
| `--source-context` | string | Source cluster context (optional, read from export metadata) | - |
| `--target-context` | string | Target cluster context (optional) | - |
| `--output` | string | Output file path (stdout if not specified) | stdout |
| `--format` | string | Output format: `text`, `script`, `instructions`, `json`, `yaml` | `text` |
| `--include-workloads` | string | Filter by workload type: `deployment`, `statefulset`, `all` | `all` |
| `--storage-class-map` | string | Storage class mapping (source:target) | - |
| `--skip-cache` | bool | Skip PVCs used by cache/temporary data | false |
| `--parallel` | bool | Generate parallel transfer commands for StatefulSets | true |
| `--verify` | bool | Add --verify flag to generated commands | true |

---

## Implementation

### Architecture

```
crane transfer-pvc explore
    ↓
1. Read export directory
    ↓
2. Parse YAML files
    ├── persistentvolumeclaim_*.yaml
    ├── deployment_*.yaml
    ├── statefulset_*.yaml
    └── export-metadata.json
    ↓
3. Analyze relationships
    ├── Which workloads use which PVCs?
    ├── StatefulSet volumeClaimTemplates
    └── PVC characteristics (size, storageClass)
    ↓
4. Generate transfer plan
    ├── Single PVCs → individual commands
    ├── StatefulSet PVCs → batch commands
    └── Add recommendations
    ↓
5. Output (text/script/json/yaml)
```

---

### Code Structure

```go
// pkg/transfer/explore/explorer.go
package explore

import (
    "context"
    "io/ioutil"
    "path/filepath"
    
    appsv1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
)

type Explorer struct {
    ExportDir        string
    SourceContext    string
    TargetContext    string
    StorageClassMap  map[string]string
}

type TransferPlan struct {
    Namespace         string
    SourceContext     string
    TargetContext     string
    PVCs              []PVCTransfer
    StatefulSetGroups []StatefulSetPVCGroup
    Recommendations   []Recommendation
}

type PVCTransfer struct {
    Name          string
    Namespace     string
    Size          string
    StorageClass  string
    UsedBy        []WorkloadReference
    TransferType  string  // "single", "statefulset"
    Command       string
    Notes         []string
}

type StatefulSetPVCGroup struct {
    StatefulSetName string
    VolumeTemplate  string
    Replicas        int
    PVCs            []PVCTransfer
    ParallelCommand string
}

type WorkloadReference struct {
    Kind      string  // Deployment, StatefulSet
    Name      string
    Namespace string
}

type Recommendation struct {
    Type    string  // "storage-class", "migration-order", "warning"
    Message string
}

func NewExplorer(exportDir string) (*Explorer, error) {
    return &Explorer{
        ExportDir:       exportDir,
        StorageClassMap: make(map[string]string),
    }, nil
}

func (e *Explorer) Discover() (*TransferPlan, error) {
    plan := &TransferPlan{
        PVCs:              make([]PVCTransfer, 0),
        StatefulSetGroups: make([]StatefulSetPVCGroup, 0),
        Recommendations:   make([]Recommendation, 0),
    }
    
    // 1. Read export metadata
    metadata, err := e.readExportMetadata()
    if err == nil {
        plan.Namespace = metadata.Namespace
        plan.SourceContext = metadata.Context
    }
    
    // Override if specified
    if e.SourceContext != "" {
        plan.SourceContext = e.SourceContext
    }
    if e.TargetContext != "" {
        plan.TargetContext = e.TargetContext
    }
    
    // 2. Discover PVCs
    pvcs, err := e.discoverPVCs()
    if err != nil {
        return nil, err
    }
    
    // 3. Discover workloads
    deployments, err := e.discoverDeployments()
    if err != nil {
        return nil, err
    }
    
    statefulsets, err := e.discoverStatefulSets()
    if err != nil {
        return nil, err
    }
    
    // 4. Map PVCs to workloads
    for _, pvc := range pvcs {
        transfer := PVCTransfer{
            Name:         pvc.Name,
            Namespace:    pvc.Namespace,
            Size:         pvc.Spec.Resources.Requests.Storage().String(),
            StorageClass: *pvc.Spec.StorageClassName,
            UsedBy:       e.findWorkloadsUsingPVC(pvc.Name, deployments, statefulsets),
        }
        
        // Generate command
        transfer.Command = e.generateTransferCommand(transfer)
        
        // Add notes
        transfer.Notes = e.analyzeNotes(transfer)
        
        plan.PVCs = append(plan.PVCs, transfer)
    }
    
    // 5. Group StatefulSet PVCs
    plan.StatefulSetGroups = e.groupStatefulSetPVCs(plan.PVCs, statefulsets)
    
    // 6. Generate recommendations
    plan.Recommendations = e.generateRecommendations(plan)
    
    return plan, nil
}

func (e *Explorer) discoverPVCs() ([]*corev1.PersistentVolumeClaim, error) {
    pvcs := make([]*corev1.PersistentVolumeClaim, 0)
    
    // Find all PVC YAML files
    files, err := filepath.Glob(filepath.Join(e.ExportDir, "persistentvolumeclaim_*.yaml"))
    if err != nil {
        return nil, err
    }
    
    for _, file := range files {
        data, err := ioutil.ReadFile(file)
        if err != nil {
            continue
        }
        
        pvc := &corev1.PersistentVolumeClaim{}
        if err := yaml.Unmarshal(data, pvc); err != nil {
            continue
        }
        
        pvcs = append(pvcs, pvc)
    }
    
    return pvcs, nil
}

func (e *Explorer) discoverDeployments() ([]*appsv1.Deployment, error) {
    deployments := make([]*appsv1.Deployment, 0)
    
    files, err := filepath.Glob(filepath.Join(e.ExportDir, "deployment_*.yaml"))
    if err != nil {
        return nil, err
    }
    
    for _, file := range files {
        data, err := ioutil.ReadFile(file)
        if err != nil {
            continue
        }
        
        deploy := &appsv1.Deployment{}
        if err := yaml.Unmarshal(data, deploy); err != nil {
            continue
        }
        
        deployments = append(deployments, deploy)
    }
    
    return deployments, nil
}

func (e *Explorer) discoverStatefulSets() ([]*appsv1.StatefulSet, error) {
    statefulsets := make([]*appsv1.StatefulSet, 0)
    
    files, err := filepath.Glob(filepath.Join(e.ExportDir, "statefulset_*.yaml"))
    if err != nil {
        return nil, err
    }
    
    for _, file := range files {
        data, err := ioutil.ReadFile(file)
        if err != nil {
            continue
        }
        
        sts := &appsv1.StatefulSet{}
        if err := yaml.Unmarshal(data, sts); err != nil {
            continue
        }
        
        statefulsets = append(statefulsets, sts)
    }
    
    return statefulsets, nil
}

func (e *Explorer) findWorkloadsUsingPVC(pvcName string, 
    deployments []*appsv1.Deployment,
    statefulsets []*appsv1.StatefulSet) []WorkloadReference {
    
    refs := make([]WorkloadReference, 0)
    
    // Check deployments
    for _, deploy := range deployments {
        for _, vol := range deploy.Spec.Template.Spec.Volumes {
            if vol.PersistentVolumeClaim != nil &&
               vol.PersistentVolumeClaim.ClaimName == pvcName {
                refs = append(refs, WorkloadReference{
                    Kind:      "Deployment",
                    Name:      deploy.Name,
                    Namespace: deploy.Namespace,
                })
            }
        }
    }
    
    // Check StatefulSets (both volumes and volumeClaimTemplates)
    for _, sts := range statefulsets {
        // Check regular volumes
        for _, vol := range sts.Spec.Template.Spec.Volumes {
            if vol.PersistentVolumeClaim != nil &&
               vol.PersistentVolumeClaim.ClaimName == pvcName {
                refs = append(refs, WorkloadReference{
                    Kind:      "StatefulSet",
                    Name:      sts.Name,
                    Namespace: sts.Namespace,
                })
            }
        }
        
        // Check volumeClaimTemplates (pattern matching)
        // data-kafka-cluster-0 matches template "data" in StatefulSet "kafka-cluster"
        for _, template := range sts.Spec.VolumeClaimTemplates {
            if e.matchesVolumeClaimTemplate(pvcName, template.Name, sts.Name) {
                refs = append(refs, WorkloadReference{
                    Kind:      "StatefulSet",
                    Name:      sts.Name,
                    Namespace: sts.Namespace,
                })
            }
        }
    }
    
    return refs
}

func (e *Explorer) matchesVolumeClaimTemplate(pvcName, templateName, stsName string) bool {
    // Pattern: {templateName}-{stsName}-{ordinal}
    // Example: data-kafka-cluster-0
    pattern := fmt.Sprintf("%s-%s-", templateName, stsName)
    return strings.HasPrefix(pvcName, pattern)
}

func (e *Explorer) generateTransferCommand(transfer PVCTransfer) string {
    var cmd strings.Builder
    
    cmd.WriteString("crane transfer-pvc \\\n")
    
    if transfer.SourceContext != "" {
        cmd.WriteString(fmt.Sprintf("  --source-context=%s \\\n", transfer.SourceContext))
    }
    
    if transfer.TargetContext != "" {
        cmd.WriteString(fmt.Sprintf("  --destination-context=%s \\\n", transfer.TargetContext))
    }
    
    cmd.WriteString(fmt.Sprintf("  --pvc-name=%s \\\n", transfer.Name))
    cmd.WriteString(fmt.Sprintf("  --pvc-namespace=%s", transfer.Namespace))
    
    // Add verify flag if enabled
    if e.verify {
        cmd.WriteString(" \\\n  --verify")
    }
    
    return cmd.String()
}

func (e *Explorer) groupStatefulSetPVCs(pvcs []PVCTransfer, 
    statefulsets []*appsv1.StatefulSet) []StatefulSetPVCGroup {
    
    groups := make([]StatefulSetPVCGroup, 0)
    
    for _, sts := range statefulsets {
        group := StatefulSetPVCGroup{
            StatefulSetName: sts.Name,
            Replicas:        int(*sts.Spec.Replicas),
            PVCs:            make([]PVCTransfer, 0),
        }
        
        // Find all PVCs belonging to this StatefulSet
        for _, pvc := range pvcs {
            for _, ref := range pvc.UsedBy {
                if ref.Kind == "StatefulSet" && ref.Name == sts.Name {
                    group.PVCs = append(group.PVCs, pvc)
                }
            }
        }
        
        if len(group.PVCs) > 0 {
            // Determine volumeClaimTemplate name
            group.VolumeTemplate = e.extractTemplateNameFromPVC(group.PVCs[0].Name, sts.Name)
            
            // Generate parallel command
            group.ParallelCommand = e.generateParallelCommand(group, sts)
            
            groups = append(groups, group)
        }
    }
    
    return groups
}

func (e *Explorer) extractTemplateNameFromPVC(pvcName, stsName string) string {
    // data-kafka-cluster-0 → "data"
    pattern := fmt.Sprintf("-%s-", stsName)
    parts := strings.Split(pvcName, pattern)
    if len(parts) >= 1 {
        return parts[0]
    }
    return ""
}

func (e *Explorer) generateParallelCommand(group StatefulSetPVCGroup, sts *appsv1.StatefulSet) string {
    var cmd strings.Builder
    
    cmd.WriteString(fmt.Sprintf("# Transfer %d PVCs for StatefulSet/%s in parallel\n", 
        group.Replicas, group.StatefulSetName))
    cmd.WriteString(fmt.Sprintf("for i in $(seq 0 %d); do\n", group.Replicas-1))
    cmd.WriteString("  crane transfer-pvc \\\n")
    cmd.WriteString(fmt.Sprintf("    --source-context=%s \\\n", e.SourceContext))
    cmd.WriteString(fmt.Sprintf("    --destination-context=%s \\\n", e.TargetContext))
    cmd.WriteString(fmt.Sprintf("    --pvc-name=%s-%s-$i \\\n", 
        group.VolumeTemplate, group.StatefulSetName))
    cmd.WriteString(fmt.Sprintf("    --pvc-namespace=%s &\n", sts.Namespace))
    cmd.WriteString("done\n")
    cmd.WriteString("wait  # Wait for all transfers to complete")
    
    return cmd.String()
}

func (e *Explorer) analyzeNotes(transfer PVCTransfer) []string {
    notes := make([]string, 0)
    
    // Check if PVC is cache
    if strings.Contains(strings.ToLower(transfer.Name), "cache") ||
       strings.Contains(strings.ToLower(transfer.Name), "tmp") {
        notes = append(notes, "⚠️  Appears to be cache data - consider if transfer is needed")
    }
    
    // Check size
    size, _ := resource.ParseQuantity(transfer.Size)
    sizeGB := size.Value() / (1024 * 1024 * 1024)
    if sizeGB > 100 {
        notes = append(notes, fmt.Sprintf("📦 Large PVC (%dGi) - transfer may take several hours", sizeGB))
    }
    
    // Check storage class
    if transfer.StorageClass != "" {
        notes = append(notes, fmt.Sprintf("💾 Source storage class: %s", transfer.StorageClass))
    }
    
    return notes
}

func (e *Explorer) generateRecommendations(plan *TransferPlan) []Recommendation {
    recs := make([]Recommendation, 0)
    
    // Storage class recommendations
    storageClasses := e.collectStorageClasses(plan.PVCs)
    if len(storageClasses) > 0 {
        recs = append(recs, Recommendation{
            Type: "storage-class",
            Message: fmt.Sprintf(
                "Source uses storage classes: %s. Verify target cluster has compatible classes.",
                strings.Join(storageClasses, ", "),
            ),
        })
    }
    
    // Migration order recommendation
    if len(plan.StatefulSetGroups) > 0 {
        recs = append(recs, Recommendation{
            Type: "migration-order",
            Message: "Scale down StatefulSets before transfer to ensure data consistency",
        })
    }
    
    // Large PVC warning
    totalSize := int64(0)
    for _, pvc := range plan.PVCs {
        size, _ := resource.ParseQuantity(pvc.Size)
        totalSize += size.Value()
    }
    totalSizeGB := totalSize / (1024 * 1024 * 1024)
    
    if totalSizeGB > 500 {
        recs = append(recs, Recommendation{
            Type: "warning",
            Message: fmt.Sprintf(
                "Total data size: %dGi - plan for adequate time window and network bandwidth",
                totalSizeGB,
            ),
        })
    }
    
    return recs
}
```

---

### Output Formatters

```go
// pkg/transfer/explore/formatter.go
package explore

type Formatter interface {
    Format(plan *TransferPlan) (string, error)
}

// Text formatter (human-readable)
type TextFormatter struct {
    ShowCommands bool
}

func (f *TextFormatter) Format(plan *TransferPlan) (string, error) {
    var out strings.Builder
    
    out.WriteString("================================================================================\n")
    out.WriteString(fmt.Sprintf("PVC Transfer Plan for namespace: %s\n", plan.Namespace))
    if plan.SourceContext != "" {
        out.WriteString(fmt.Sprintf("Source cluster: %s\n", plan.SourceContext))
    }
    if plan.TargetContext != "" {
        out.WriteString(fmt.Sprintf("Target cluster: %s\n", plan.TargetContext))
    }
    out.WriteString("================================================================================\n\n")
    
    out.WriteString(fmt.Sprintf("Found %d PVCs to transfer:\n\n", len(plan.PVCs)))
    
    // Single PVCs
    singlePVCs := e.filterSinglePVCs(plan.PVCs, plan.StatefulSetGroups)
    for i, pvc := range singlePVCs {
        out.WriteString(fmt.Sprintf("%d. %s (%s, storageClass: %s)\n", 
            i+1, pvc.Name, pvc.Size, pvc.StorageClass))
        
        if len(pvc.UsedBy) > 0 {
            out.WriteString(fmt.Sprintf("   Used by: %s/%s\n", 
                pvc.UsedBy[0].Kind, pvc.UsedBy[0].Name))
        }
        
        // Notes
        for _, note := range pvc.Notes {
            out.WriteString(fmt.Sprintf("   %s\n", note))
        }
        
        if f.ShowCommands {
            out.WriteString("\n   Transfer command:\n\n")
            out.WriteString("   " + strings.ReplaceAll(pvc.Command, "\n", "\n   ") + "\n")
        }
        
        out.WriteString("\n")
    }
    
    // StatefulSet groups
    for _, group := range plan.StatefulSetGroups {
        out.WriteString(fmt.Sprintf("StatefulSet: %s (%d replicas, %d PVCs)\n",
            group.StatefulSetName, group.Replicas, len(group.PVCs)))
        
        if f.ShowCommands {
            out.WriteString("\n   Parallel transfer command:\n\n")
            out.WriteString("   " + strings.ReplaceAll(group.ParallelCommand, "\n", "\n   ") + "\n")
        }
        
        out.WriteString("\n")
    }
    
    // Recommendations
    if len(plan.Recommendations) > 0 {
        out.WriteString("================================================================================\n")
        out.WriteString("Recommendations:\n")
        out.WriteString("================================================================================\n\n")
        
        for _, rec := range plan.Recommendations {
            out.WriteString(fmt.Sprintf("• %s\n", rec.Message))
        }
    }
    
    return out.String(), nil
}

// Script formatter (executable bash)
type ScriptFormatter struct {
    IncludeComments bool
}

func (f *ScriptFormatter) Format(plan *TransferPlan) (string, error) {
    var out strings.Builder
    
    out.WriteString("#!/bin/bash\n")
    out.WriteString("# PVC Transfer Script\n")
    out.WriteString(fmt.Sprintf("# Generated for namespace: %s\n", plan.Namespace))
    out.WriteString("# DO NOT RUN WITHOUT REVIEWING\n\n")
    
    out.WriteString("set -e  # Exit on error\n\n")
    
    // Recommendations as comments
    if f.IncludeComments {
        out.WriteString("# IMPORTANT: Before running this script:\n")
        for _, rec := range plan.Recommendations {
            out.WriteString(fmt.Sprintf("# - %s\n", rec.Message))
        }
        out.WriteString("\n")
    }
    
    // Single PVCs
    singlePVCs := filterSinglePVCs(plan.PVCs, plan.StatefulSetGroups)
    for i, pvc := range singlePVCs {
        out.WriteString(fmt.Sprintf("# Transfer PVC %d/%d: %s\n", 
            i+1, len(singlePVCs), pvc.Name))
        out.WriteString(pvc.Command + "\n\n")
    }
    
    // StatefulSet groups
    for _, group := range plan.StatefulSetGroups {
        out.WriteString(group.ParallelCommand + "\n\n")
    }
    
    out.WriteString("echo \"All transfers completed successfully\"\n")
    
    return out.String(), nil
}

// JSON formatter
type JSONFormatter struct{}

func (f *JSONFormatter) Format(plan *TransferPlan) (string, error) {
    data, err := json.MarshalIndent(plan, "", "  ")
    if err != nil {
        return "", err
    }
    return string(data), nil
}

// YAML formatter
type YAMLFormatter struct{}

func (f *YAMLFormatter) Format(plan *TransferPlan) (string, error) {
    data, err := yaml.Marshal(plan)
    if err != nil {
        return "", err
    }
    return string(data), nil
}

// Migration Instructions formatter (like crane transform)
// SIMPLE - just PVC transfers, NO orchestration
type InstructionsFormatter struct{}

func (f *InstructionsFormatter) Format(plan *TransferPlan) (string, error) {
    var out strings.Builder
    
    // Header
    out.WriteString("# PVC Migration Instructions\n")
    out.WriteString("# Generated by: crane transfer-pvc explore\n")
    out.WriteString("# Similar to crane transform - edit and apply with: crane transfer-pvc --instructions=pvc-migration.yaml\n")
    out.WriteString(fmt.Sprintf("# Namespace: %s\n\n", plan.Namespace))
    
    // Default source/destination (can be overridden per transfer)
    out.WriteString("# Default source/destination (can be overridden per PVC)\n")
    out.WriteString("source:\n")
    out.WriteString(fmt.Sprintf("  context: %s\n", plan.SourceContext))
    out.WriteString(fmt.Sprintf("  namespace: %s\n\n", plan.Namespace))
    
    out.WriteString("destination:\n")
    out.WriteString(fmt.Sprintf("  context: %s\n", plan.TargetContext))
    out.WriteString(fmt.Sprintf("  namespace: %s\n\n", plan.Namespace))
    
    // Storage class mappings
    out.WriteString("# Storage class mappings (optional)\n")
    out.WriteString("storageClassMappings:\n")
    storageClasses := collectStorageClasses(plan.PVCs)
    for _, sc := range storageClasses {
        out.WriteString(fmt.Sprintf("# - source: %s\n", sc))
        out.WriteString("#   target: standard-rwo\n")
    }
    out.WriteString("\n")
    
    // PVCs to transfer
    out.WriteString("# PVCs to transfer\n")
    out.WriteString("transfers:\n")
    
    // Single PVCs
    singlePVCs := filterSinglePVCs(plan.PVCs, plan.StatefulSetGroups)
    for _, pvc := range singlePVCs {
        // Comment with context
        workloadInfo := ""
        if len(pvc.UsedBy) > 0 {
            workloadInfo = fmt.Sprintf(" Used by %s/%s", pvc.UsedBy[0].Kind, pvc.UsedBy[0].Name)
        }
        out.WriteString(fmt.Sprintf("  # %s:%s (%s, %s)\n", 
            pvc.Name, workloadInfo, pvc.Size, pvc.StorageClass))
        
        out.WriteString(fmt.Sprintf("  - pvc: %s\n", pvc.Name))
        out.WriteString("    method: sync  # cluster-to-cluster (default)\n")
        out.WriteString("    # source: {}  # Inherits from default above\n")
        out.WriteString("    # destination: {}  # Inherits from default above\n")
        out.WriteString("    verify: true\n")
        
        // Alternative methods as comments
        out.WriteString("    \n")
        out.WriteString("    # Alternative methods (uncomment to use):\n")
        out.WriteString("    # Export to local:\n")
        out.WriteString("    # method: export\n")
        out.WriteString("    # destination:\n")
        out.WriteString("    #   type: local\n")
        out.WriteString(fmt.Sprintf("    #   path: ~/backups/%s.tar.gz\n", pvc.Name))
        out.WriteString("    #   compress: true\n")
        out.WriteString("    \n")
        out.WriteString("    # Export to S3:\n")
        out.WriteString("    # method: export\n")
        out.WriteString("    # destination:\n")
        out.WriteString("    #   type: s3\n")
        out.WriteString("    #   bucket: my-backup-bucket\n")
        out.WriteString(fmt.Sprintf("    #   path: %s/\n", pvc.Name))
        out.WriteString("    #   credentialsSecret: s3-credentials\n")
        
        // Skip suggestion for cache
        if containsIgnoreCase(pvc.Name, "cache", "tmp") {
            out.WriteString("\n    # Consider if cache needs transfer (can be rebuilt):\n")
            out.WriteString("    # skip: true\n")
        }
        
        out.WriteString("\n")
    }
    
    // StatefulSet PVCs
    for _, group := range plan.StatefulSetGroups {
        out.WriteString(fmt.Sprintf("  # StatefulSet PVCs: %s-%s-{0..%d}\n", 
            group.VolumeTemplate, group.StatefulSetName, group.Replicas-1))
        workloadInfo := ""
        if len(group.PVCs) > 0 && len(group.PVCs[0].UsedBy) > 0 {
            workloadInfo = fmt.Sprintf(" Used by %s/%s", 
                group.PVCs[0].UsedBy[0].Kind, group.PVCs[0].UsedBy[0].Name)
        }
        if len(group.PVCs) > 0 {
            out.WriteString(fmt.Sprintf("  #%s (%s each, %s)\n", 
                workloadInfo, group.PVCs[0].Size, group.PVCs[0].StorageClass))
        }
        
        // Expand each replica
        for i := 0; i < group.Replicas; i++ {
            pvcName := fmt.Sprintf("%s-%s-%d", group.VolumeTemplate, group.StatefulSetName, i)
            out.WriteString(fmt.Sprintf("  - pvc: %s\n", pvcName))
            out.WriteString("    method: sync\n")
            out.WriteString("    verify: true\n")
            if i < group.Replicas-1 {
                out.WriteString("  \n")
            }
        }
        
        out.WriteString("\n")
    }
    
    // Global transfer options
    out.WriteString("# Global transfer options (apply to all unless overridden)\n")
    out.WriteString("options:\n")
    out.WriteString("  # bandwidthLimit: 100M\n")
    out.WriteString("  # compress: false\n")
    out.WriteString("  verify: true\n")
    
    return out.String(), nil
}
```

---

## CLI Command Implementation

```go
// cmd/transfer-pvc/explore_cmd.go
package transfer_pvc

import (
    "fmt"
    "os"
    
    "github.com/spf13/cobra"
    "github.com/konveyor/crane/pkg/transfer/explore"
)

func NewExploreCommand() *cobra.Command {
    var (
        exportDir       string
        sourceContext   string
        targetContext   string
        outputFile      string
        format          string
        storageClassMap string
        skipCache       bool
        parallel        bool
        verify          bool
    )
    
    cmd := &cobra.Command{
        Use:   "explore",
        Short: "Discover PVCs from crane export and generate transfer commands",
        Long: `Analyze crane export directory to discover PVCs and generate ready-to-use
transfer commands.

This command helps you understand which PVCs need to be transferred and
provides copy-paste-ready commands to perform the transfers.

Examples:
  # Discover PVCs and show transfer commands
  crane transfer-pvc explore --export-dir=myapp/

  # Generate executable script
  crane transfer-pvc explore --export-dir=myapp/ \
    --target-context=dest \
    --output=transfer.sh \
    --format=script

  # Output as JSON for automation
  crane transfer-pvc explore --export-dir=myapp/ --format=json
`,
        RunE: func(cmd *cobra.Command, args []string) error {
            // Create explorer
            explorer, err := explore.NewExplorer(exportDir)
            if err != nil {
                return err
            }
            
            // Set options
            explorer.SourceContext = sourceContext
            explorer.TargetContext = targetContext
            explorer.SkipCache = skipCache
            explorer.Parallel = parallel
            explorer.Verify = verify
            
            // Parse storage class mapping
            if storageClassMap != "" {
                parts := strings.Split(storageClassMap, ":")
                if len(parts) == 2 {
                    explorer.StorageClassMap[parts[0]] = parts[1]
                }
            }
            
            // Discover
            plan, err := explorer.Discover()
            if err != nil {
                return fmt.Errorf("discovery failed: %w", err)
            }
            
            // Format output
            var formatter explore.Formatter
            switch format {
            case "text":
                formatter = &explore.TextFormatter{ShowCommands: true}
            case "script":
                formatter = &explore.ScriptFormatter{IncludeComments: true}
            case "json":
                formatter = &explore.JSONFormatter{}
            case "yaml":
                formatter = &explore.YAMLFormatter{}
            default:
                return fmt.Errorf("unknown format: %s", format)
            }
            
            output, err := formatter.Format(plan)
            if err != nil {
                return err
            }
            
            // Write output
            if outputFile != "" {
                if err := os.WriteFile(outputFile, []byte(output), 0644); err != nil {
                    return err
                }
                fmt.Printf("Transfer plan written to: %s\n", outputFile)
            } else {
                fmt.Print(output)
            }
            
            return nil
        },
    }
    
    cmd.Flags().StringVar(&exportDir, "export-dir", "", "Path to crane export directory (required)")
    cmd.Flags().StringVar(&sourceContext, "source-context", "", "Source cluster context (optional)")
    cmd.Flags().StringVar(&targetContext, "target-context", "", "Target cluster context (optional)")
    cmd.Flags().StringVar(&outputFile, "output", "", "Output file (stdout if not specified)")
    cmd.Flags().StringVar(&format, "format", "text", "Output format: text, script, json, yaml")
    cmd.Flags().StringVar(&storageClassMap, "storage-class-map", "", "Storage class mapping (source:target)")
    cmd.Flags().BoolVar(&skipCache, "skip-cache", false, "Skip PVCs that appear to be caches")
    cmd.Flags().BoolVar(&parallel, "parallel", true, "Generate parallel commands for StatefulSets")
    cmd.Flags().BoolVar(&verify, "verify", true, "Add --verify flag to commands")
    
    cmd.MarkFlagRequired("export-dir")
    
    return cmd
}
```

---

## Example Outputs

### Example 1: Simple Application

**Export directory structure:**
```
myapp/
├── deployment_frontend.yaml
├── deployment_api.yaml
├── deployment_postgres.yaml
├── persistentvolumeclaim_postgres-data.yaml
├── service_*.yaml
└── export-metadata.json
```

**Command:**
```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=dest-cluster
```

**Output:**
```
================================================================================
PVC Transfer Plan for namespace: myapp
Source cluster: source-cluster
Target cluster: dest-cluster
================================================================================

Found 1 PVC to transfer:

1. postgres-data (50Gi, storageClass: gp2)
   Used by: Deployment/postgres
   💾 Source storage class: gp2

   Transfer command:

   crane transfer-pvc \
     --source-context=source-cluster \
     --destination-context=dest-cluster \
     --pvc-name=postgres-data \
     --pvc-namespace=myapp \
     --verify

================================================================================
Recommendations:
================================================================================

• Source uses storage classes: gp2. Verify target cluster has compatible classes.
• Scale down Deployment/postgres before transfer to ensure data consistency
```

---

### Example 2: StatefulSet Application

**Export directory:**
```
kafka/
├── statefulset_kafka-cluster.yaml
├── persistentvolumeclaim_data-kafka-cluster-0.yaml
├── persistentvolumeclaim_data-kafka-cluster-1.yaml
├── persistentvolumeclaim_data-kafka-cluster-2.yaml
├── service_kafka.yaml
└── export-metadata.json
```

**Command:**
```bash
crane transfer-pvc explore \
  --export-dir=kafka/ \
  --target-context=dest \
  --format=script \
  --output=transfer-kafka.sh
```

**Output (transfer-kafka.sh):**
```bash
#!/bin/bash
# PVC Transfer Script
# Generated for namespace: kafka
# DO NOT RUN WITHOUT REVIEWING

set -e  # Exit on error

# IMPORTANT: Before running this script:
# - Source uses storage classes: gp2. Verify target cluster has compatible classes.
# - Scale down StatefulSets before transfer to ensure data consistency
# - Total data size: 300Gi - plan for adequate time window and network bandwidth

# Transfer PVCs for StatefulSet/kafka-cluster in parallel
for i in $(seq 0 2); do
  crane transfer-pvc \
    --source-context=source-cluster \
    --destination-context=dest \
    --pvc-name=data-kafka-cluster-$i \
    --pvc-namespace=kafka &
done
wait  # Wait for all transfers to complete

echo "All transfers completed successfully"
```

---

### Example 3: Migration Instructions File (like crane transform)

**Command:**
```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --format=instructions \
  --output=pvc-migration.yaml
```

**Output (pvc-migration.yaml):**
```yaml
# PVC Migration Instructions
# Generated by: crane transfer-pvc explore
# Similar to crane transform - edit and apply with: crane transfer-pvc --instructions=pvc-migration.yaml

# Default source/destination (can be overridden per PVC)
source:
  context: source-cluster
  namespace: myapp

destination:
  context: dest-cluster
  namespace: myapp

# Storage class mappings (optional)
storageClassMappings:
# - source: gp2
#   target: standard-rwo

# PVCs to transfer
transfers:
  # postgres-data: Used by Deployment/postgres (50Gi, gp2)
  - pvc: postgres-data
    method: sync  # cluster-to-cluster (default)
    # source: {}  # Inherits from default above
    # destination: {}  # Inherits from default above
    verify: true
    
    # Alternative methods (uncomment to use):
    # Export to local:
    # method: export
    # destination:
    #   type: local
    #   path: ~/backups/postgres-data.tar.gz
    #   compress: true
    
    # Export to S3:
    # method: export
    # destination:
    #   type: s3
    #   bucket: my-backup-bucket
    #   path: postgres-data/
    #   credentialsSecret: s3-credentials

  # redis-cache: Used by Deployment/redis (10Gi, gp2)
  # Consider if cache needs transfer (can be rebuilt)
  - pvc: redis-cache
    skip: true
    # skipReason: Cache data - can be rebuilt on target

  # StatefulSet PVCs: data-kafka-cluster-{0,1,2}
  # Used by StatefulSet/kafka-cluster (100Gi each, gp2)
  - pvc: data-kafka-cluster-0
    method: sync
    verify: true
  
  - pvc: data-kafka-cluster-1
    method: sync
    verify: true
  
  - pvc: data-kafka-cluster-2
    method: sync
    verify: true

# Global transfer options (apply to all unless overridden)
options:
  # bandwidthLimit: 100M
  # compress: false
  verify: true
```

**Simpler alternative - just list of transfers:**
```yaml
# Minimal format - just the essentials
transfers:
  - pvc: postgres-data
    source: source-cluster
    destination: dest-cluster
    
  - pvc: redis-cache
    skip: true
    
  # StatefulSet PVCs - pattern expansion
  - pvc: data-kafka-cluster-*  # Expands to 0,1,2
    source: source-cluster
    destination: dest-cluster
    replicas: 3  # How many to expand
```

**Using the migration instructions:**

```bash
# Execute all transfers from instructions file
crane transfer-pvc --instructions=pvc-migration.yaml

# Dry-run (show what would be done)
crane transfer-pvc --instructions=pvc-migration.yaml --dry-run

# Execute only specific PVCs
crane transfer-pvc --instructions=pvc-migration.yaml --include=postgres-data

# Skip certain PVCs
crane transfer-pvc --instructions=pvc-migration.yaml --exclude=redis-cache
```

**Benefits of instructions file:**
- ✅ **Editable** - Review and modify before execution
- ✅ **Multiple methods** - cluster-to-cluster, local, cloud (as comments)
- ✅ **Selective execution** - Skip or include specific PVCs
- ✅ **Version control** - Commit to git, track changes
- ✅ **Reusable** - Same file for dev/staging/prod (adjust contexts)
- ✅ **Simple** - Just transfer definitions, no orchestration

---

### Example 4: JSON Output (for automation)

**Command:**
```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --format=json
```

**Output:**
```json
{
  "namespace": "myapp",
  "sourceContext": "source-cluster",
  "targetContext": "dest-cluster",
  "pvcs": [
    {
      "name": "postgres-data",
      "namespace": "myapp",
      "size": "50Gi",
      "storageClass": "gp2",
      "usedBy": [
        {
          "kind": "Deployment",
          "name": "postgres",
          "namespace": "myapp"
        }
      ],
      "transferType": "single",
      "command": "crane transfer-pvc \\\n  --source-context=source-cluster \\\n  --destination-context=dest-cluster \\\n  --pvc-name=postgres-data \\\n  --pvc-namespace=myapp \\\n  --verify",
      "notes": [
        "💾 Source storage class: gp2"
      ]
    }
  ],
  "statefulSetGroups": [],
  "recommendations": [
    {
      "type": "storage-class",
      "message": "Source uses storage classes: gp2. Verify target cluster has compatible classes."
    }
  ]
}
```

---

## Advanced Features

### Storage Class Detection & Mapping

```bash
# Detect source storage classes and suggest mappings
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --detect-target-cluster

# Output includes:
# Detected target cluster type: GKE (Google Kubernetes Engine)
# Recommended storage class mapping:
#   gp2 (AWS EBS) → standard-rwo (Google Persistent Disk)
#
# Apply with:
#   --storage-class-map=gp2:standard-rwo
```

### Migration Workflow Generator

```bash
# Generate complete migration workflow script
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --workflow=full \
  --output=migrate.sh

# migrate.sh includes:
# 1. Pre-migration checks
# 2. Scale down source workloads
# 3. PVC transfers
# 4. Verification
# 5. Scale up target workloads
```

---

## Integration with crane apply

```bash
# Complete migration workflow:

# 1. Export
crane export --context=source --namespace=myapp --export-dir=myapp/

# 2. Explore and plan
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=dest \
  --output=transfer-plan.sh

# 3. Review plan
cat transfer-plan.sh

# 4. Apply stateless resources first
crane apply --export-dir=myapp/ --context=dest

# 5. Execute PVC transfers
bash transfer-plan.sh

# 6. Verify
crane transfer-pvc verify --export-dir=myapp/ --context=dest
```

---

## Implementation Estimate

| Task | Effort | Priority |
|------|--------|----------|
| Core explorer (discover PVCs, workloads) | 1 day | High |
| Relationship mapping (PVC → workload) | 4 hours | High |
| Command generator | 4 hours | High |
| StatefulSet grouping | 4 hours | High |
| Text formatter | 2 hours | High |
| Script formatter | 2 hours | High |
| JSON/YAML formatters | 2 hours | Medium |
| CLI command | 2 hours | High |
| Recommendations engine | 4 hours | Medium |
| Storage class detection | 4 hours | Low |
| Tests & documentation | 1 day | High |
| **Total** | **3-4 days** | |

---

## Benefits

### For Users

✅ **No manual discovery** - Automatic PVC identification  
✅ **Copy-paste ready** - Commands ready to execute  
✅ **Best practices** - Parallel transfers, verification enabled  
✅ **Safety warnings** - Large PVCs, cache detection  
✅ **Time estimates** - Based on PVC sizes  

### For Automation

✅ **JSON/YAML output** - Machine-readable format  
✅ **Scriptable** - Generate executable bash scripts  
✅ **CI/CD friendly** - Easy to integrate  

---

## Summary

`crane transfer-pvc explore` bridges the gap between `crane export` and `crane transfer-pvc`:

1. **Discovers** PVCs from export directory
2. **Analyzes** which workloads use which PVCs
3. **Groups** StatefulSet PVCs for parallel transfer
4. **Generates** ready-to-use transfer commands
5. **Provides** recommendations and warnings
6. **Outputs** in multiple formats (text, script, JSON, YAML)

**Implementation:** 3-4 days  
**Value:** High - eliminates manual discovery and reduces migration errors
