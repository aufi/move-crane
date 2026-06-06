package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/yaml"
)

// PluginMetadata describes the plugin
type PluginMetadata struct {
	Name        string
	Version     string
	Description string
}

// PluginRequest is the input to the plugin
type PluginRequest struct {
	unstructured.Unstructured
	Extras map[string]string `json:"extras,omitempty"`
}

// PluginResponse is returned by the plugin
type PluginResponse struct {
	Version      string                        `json:"version,omitempty"`
	IsWhiteOut   bool                          `json:"isWhiteOut,omitempty"`
	Patches      []byte                        `json:"patches,omitempty"`
	NewResources []unstructured.Unstructured   `json:"newResources,omitempty"`
}

// Plugin interface
type Plugin interface {
	Run(PluginRequest) (PluginResponse, error)
	Metadata() PluginMetadata
}

// BuildConfigConverterPlugin converts BuildConfig to Shipwright Build
type BuildConfigConverterPlugin struct {
	HelmChartPath string
}

// Metadata returns plugin metadata
func (p *BuildConfigConverterPlugin) Metadata() PluginMetadata {
	return PluginMetadata{
		Name:        "BuildConfigConverter",
		Version:     "v1.0.0",
		Description: "Converts OpenShift BuildConfig to Shipwright Build using Helm templates",
	}
}

// Run executes the plugin logic
func (p *BuildConfigConverterPlugin) Run(req PluginRequest) (PluginResponse, error) {
	resp := PluginResponse{
		Version: "v1",
	}

	// Only process BuildConfig resources
	if req.GetKind() != "BuildConfig" {
		return resp, nil
	}

	fmt.Printf("Processing BuildConfig: %s/%s\n", req.GetNamespace(), req.GetName())

	// Extract BuildConfig spec
	spec, found, err := unstructured.NestedMap(req.Object, "spec")
	if err != nil || !found {
		return resp, fmt.Errorf("failed to get BuildConfig spec: %w", err)
	}

	// Extract metadata
	metadata, found, err := unstructured.NestedMap(req.Object, "metadata")
	if err != nil || !found {
		return resp, fmt.Errorf("failed to get BuildConfig metadata: %w", err)
	}

	// Build Helm values from BuildConfig
	values := p.buildHelmValues(req.GetName(), req.GetNamespace(), metadata, spec)

	// Write values to temp file
	valuesFile, err := p.writeHelmValues(values)
	if err != nil {
		return resp, fmt.Errorf("failed to write helm values: %w", err)
	}
	defer os.Remove(valuesFile)

	// Execute helm template
	buildYAML, err := p.executeHelmTemplate(valuesFile)
	if err != nil {
		return resp, fmt.Errorf("failed to execute helm template: %w", err)
	}

	// Parse generated Build resource(s)
	builds, err := p.parseGeneratedResources(buildYAML)
	if err != nil {
		return resp, fmt.Errorf("failed to parse generated resources: %w", err)
	}

	// Return response with new Build resource and whiteout for BuildConfig
	resp.NewResources = builds
	resp.IsWhiteOut = true // Delete original BuildConfig

	fmt.Printf("✓ Converted BuildConfig %s to Shipwright Build\n", req.GetName())

	return resp, nil
}

// buildHelmValues creates Helm values from BuildConfig
func (p *BuildConfigConverterPlugin) buildHelmValues(name, namespace string, metadata, spec map[string]interface{}) map[string]interface{} {
	// Extract labels if present
	labels := make(map[string]interface{})
	if meta, ok := metadata["labels"].(map[string]interface{}); ok {
		labels = meta
	}

	values := map[string]interface{}{
		"buildconfig": map[string]interface{}{
			"name":      name,
			"namespace": namespace,
			"labels":    labels,
			"strategy":  spec["strategy"],
			"source":    spec["source"],
			"output":    spec["output"],
		},
		"conversion": map[string]interface{}{
			"dockerStrategyName": "buildah",
			"sourceStrategyName": "source-to-image",
			"addAnnotations":     true,
			"annotationPrefix":   "crane.konveyor.io",
			"strategyKind":       "ClusterBuildStrategy",
			"timeout":            "10m",
			"retention": map[string]interface{}{
				"succeededLimit": 3,
				"failedLimit":    3,
			},
		},
		"advanced": map[string]interface{}{
			"createServiceAccount": false,
		},
	}

	return values
}

// writeHelmValues writes values to a temporary file
func (p *BuildConfigConverterPlugin) writeHelmValues(values map[string]interface{}) (string, error) {
	valuesYAML, err := yaml.Marshal(values)
	if err != nil {
		return "", err
	}

	tmpFile, err := os.CreateTemp("", "helm-values-*.yaml")
	if err != nil {
		return "", err
	}
	defer tmpFile.Close()

	if _, err := tmpFile.Write(valuesYAML); err != nil {
		return "", err
	}

	return tmpFile.Name(), nil
}

// executeHelmTemplate runs helm template command
func (p *BuildConfigConverterPlugin) executeHelmTemplate(valuesFile string) ([]byte, error) {
	cmd := exec.Command("helm", "template", "shipwright-build",
		p.HelmChartPath,
		"-f", valuesFile,
	)

	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("helm template failed: %s: %w", stderr.String(), err)
	}

	return out.Bytes(), nil
}

// parseGeneratedResources parses YAML output from helm template
func (p *BuildConfigConverterPlugin) parseGeneratedResources(yamlBytes []byte) ([]unstructured.Unstructured, error) {
	resources := []unstructured.Unstructured{}

	// Split YAML documents
	docs := bytes.Split(yamlBytes, []byte("\n---\n"))

	for _, doc := range docs {
		doc = bytes.TrimSpace(doc)
		if len(doc) == 0 {
			continue
		}

		// Skip YAML comments
		if bytes.HasPrefix(doc, []byte("#")) {
			continue
		}

		var resource unstructured.Unstructured
		if err := yaml.Unmarshal(doc, &resource); err != nil {
			return nil, fmt.Errorf("failed to parse YAML document: %w", err)
		}

		// Skip empty resources
		if resource.GetKind() == "" {
			continue
		}

		resources = append(resources, resource)
	}

	return resources, nil
}

// getHelmChartPath returns the path to the Helm chart
func getHelmChartPath() string {
	// Try environment variable first
	if path := os.Getenv("HELM_CHART_PATH"); path != "" {
		return path
	}

	// Try relative to executable
	execPath, err := os.Executable()
	if err == nil {
		// Assume structure: plugin/buildconfig-converter
		// Helm chart at: helm-chart/shipwright-build/
		pluginDir := filepath.Dir(execPath)
		helmPath := filepath.Join(pluginDir, "..", "helm-chart", "shipwright-build")
		if _, err := os.Stat(helmPath); err == nil {
			return helmPath
		}
	}

	// Default to home directory
	homeDir, _ := os.UserHomeDir()
	return filepath.Join(homeDir, "crane-buildconfig-converter", "helm-chart", "shipwright-build")
}

func main() {
	helmChartPath := getHelmChartPath()

	fmt.Printf("BuildConfigConverter Plugin\n")
	fmt.Printf("Helm chart path: %s\n", helmChartPath)

	plugin := &BuildConfigConverterPlugin{
		HelmChartPath: helmChartPath,
	}

	// Check if running in test mode
	if len(os.Args) > 1 && os.Args[1] == "--test" {
		testPlugin(plugin)
		return
	}

	// In real crane integration, this would be:
	// transform.RunMain(plugin)

	fmt.Println("Plugin initialized successfully")
	fmt.Println("Note: This is a prototype. NewResources support requires crane v0.1.0+")
}

// testPlugin runs a simple test
func testPlugin(plugin *BuildConfigConverterPlugin) {
	fmt.Println("\n=== Running plugin test ===\n")

	if len(os.Args) < 3 {
		fmt.Println("Usage: buildconfig-converter --test <buildconfig.yaml>")
		os.Exit(1)
	}

	bcFile := os.Args[2]
	data, err := os.ReadFile(bcFile)
	if err != nil {
		fmt.Printf("Error reading file: %v\n", err)
		os.Exit(1)
	}

	var bc unstructured.Unstructured
	if err := yaml.Unmarshal(data, &bc); err != nil {
		fmt.Printf("Error parsing YAML: %v\n", err)
		os.Exit(1)
	}

	req := PluginRequest{
		Unstructured: bc,
	}

	resp, err := plugin.Run(req)
	if err != nil {
		fmt.Printf("Error running plugin: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nPlugin Response:\n")
	fmt.Printf("  IsWhiteOut: %v\n", resp.IsWhiteOut)
	fmt.Printf("  NewResources: %d\n", len(resp.NewResources))

	for i, res := range resp.NewResources {
		fmt.Printf("\n--- Generated Resource %d ---\n", i+1)
		fmt.Printf("Kind: %s\n", res.GetKind())
		fmt.Printf("Name: %s\n", res.GetName())
		fmt.Printf("Namespace: %s\n", res.GetNamespace())

		yamlBytes, _ := yaml.Marshal(res.Object)
		fmt.Printf("\n%s\n", string(yamlBytes))
	}

	fmt.Println("\n=== Test completed successfully ===")
}
