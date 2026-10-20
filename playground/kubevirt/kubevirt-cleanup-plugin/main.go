package main

import (
	"encoding/json"
	"strings"

	jsonpatch "github.com/evanphx/json-patch"
	"github.com/konveyor/crane-lib/transform"
	"github.com/konveyor/crane-lib/transform/cli"
)

func main() {
	cli.RunAndExit(cli.NewCustomPlugin("KubeVirtCleanupPlugin", "v0.1.0", nil, Run))
}

func Run(request transform.PluginRequest) (transform.PluginResponse, error) {
	if request.GetAPIVersion() == "kubevirt.io/v1" && request.GetKind() == "VirtualMachineInstance" {
		return transform.PluginResponse{Version: "v1", IsWhiteOut: true}, nil
	}
	if request.GetAPIVersion() != "kubevirt.io/v1" || request.GetKind() != "VirtualMachine" {
		return transform.PluginResponse{Version: "v1"}, nil
	}

	patches := jsonpatch.Patch{}
	for _, path := range []string{
		"/metadata/finalizers",
		"/metadata/uid",
		"/metadata/resourceVersion",
		"/metadata/generation",
		"/metadata/creationTimestamp",
		"/metadata/managedFields",
		"/status",
	} {
		if fieldExists(request.Object, strings.Split(strings.TrimPrefix(path, "/"), "/")...) {
			var err error
			patches, err = appendRemove(patches, path)
			if err != nil {
				return transform.PluginResponse{}, err
			}
		}
	}

	for _, key := range []string{
		"kubevirt.io/latest-observed-api-version",
		"kubevirt.io/storage-observed-api-version",
		"kubevirt.io/vm-generation",
		"kubevirt.io/pci-topology-version",
	} {
		if fieldExists(request.Object, "metadata", "annotations", key) {
			path := "/metadata/annotations/" + strings.ReplaceAll(strings.ReplaceAll(key, "~", "~0"), "/", "~1")
			var err error
			patches, err = appendRemove(patches, path)
			if err != nil {
				return transform.PluginResponse{}, err
			}
		}
	}

	return transform.PluginResponse{Version: "v1", Patches: patches}, nil
}

func appendRemove(patches jsonpatch.Patch, path string) (jsonpatch.Patch, error) {
	data, err := json.Marshal([]map[string]string{{"op": "remove", "path": path}})
	if err != nil {
		return nil, err
	}
	operation, err := jsonpatch.DecodePatch(data)
	if err != nil {
		return nil, err
	}
	return append(patches, operation...), nil
}

func fieldExists(value map[string]interface{}, path ...string) bool {
	current := value
	for index, part := range path {
		item, found := current[part]
		if !found {
			return false
		}
		if index == len(path)-1 {
			return true
		}
		next, ok := item.(map[string]interface{})
		if !ok {
			return false
		}
		current = next
	}
	return false
}
