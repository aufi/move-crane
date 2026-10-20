package main

import (
	"testing"

	"github.com/konveyor/crane-lib/transform"
)

func TestRunCleansVirtualMachineMetadata(t *testing.T) {
	request := transform.PluginRequest{Unstructured: mapToUnstructured(map[string]interface{}{
		"apiVersion": "kubevirt.io/v1",
		"kind":       "VirtualMachine",
		"metadata": map[string]interface{}{
			"finalizers": []interface{}{"kubevirt.io/virtualMachineControllerFinalize"},
			"uid":        "source-uid",
			"annotations": map[string]interface{}{
				"kubevirt.io/vm-generation": "1",
			},
		},
		"status": map[string]interface{}{},
	})}

	response, err := Run(request)
	if err != nil {
		t.Fatal(err)
	}
	if response.IsWhiteOut || len(response.Patches) != 4 {
		t.Fatalf("unexpected response: %#v", response)
	}
}

func TestRunWhiteoutsVirtualMachineInstance(t *testing.T) {
	request := transform.PluginRequest{Unstructured: mapToUnstructured(map[string]interface{}{
		"apiVersion": "kubevirt.io/v1",
		"kind":       "VirtualMachineInstance",
	})}

	response, err := Run(request)
	if err != nil {
		t.Fatal(err)
	}
	if !response.IsWhiteOut {
		t.Fatal("VirtualMachineInstance must be whiteouted")
	}
}
