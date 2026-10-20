package main

import "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

func mapToUnstructured(object map[string]interface{}) unstructured.Unstructured {
	return unstructured.Unstructured{Object: object}
}
