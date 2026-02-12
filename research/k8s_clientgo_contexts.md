# Working with Kubernetes Contexts in client-go

This guide explains how to work with Kubernetes contexts using the client-go library.

## What are Kubernetes Contexts?

A **context** in Kubernetes is a combination of three elements:

- **Cluster** - which Kubernetes cluster to connect to
- **User** - authentication credentials to use
- **Namespace** - default namespace for operations

Contexts are defined in your kubeconfig file (typically `~/.kube/config`) and allow you to easily switch between different clusters, users, and namespaces.

## Kubeconfig Structure

A kubeconfig file contains:

```yaml
clusters:
- name: production
  cluster:
    server: https://prod.example.com:6443
    certificate-authority: /path/to/ca.crt

- name: development
  cluster:
    server: https://dev.example.com:6443

users:
- name: admin
  user:
    client-certificate: /path/to/cert
    client-key: /path/to/key

- name: developer
  user:
    token: abc123xyz

contexts:
- name: prod-admin
  context:
    cluster: production
    user: admin
    namespace: default

- name: dev-developer
  context:
    cluster: development
    user: developer
    namespace: development

current-context: dev-developer
```

## Basic Usage

### 1. Using the Current Context

The simplest way to create a client using the current context from kubeconfig:

```go
package main

import (
    "context"
    "fmt"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    // Load config from default location (~/.kube/config)
    // Uses the current-context from kubeconfig
    config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
    if err != nil {
        panic(err.Error())
    }

    // Create clientset
    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        panic(err.Error())
    }

    // Use the client
    pods, err := clientset.CoreV1().Pods("default").List(context.TODO(), metav1.ListOptions{})
    if err != nil {
        panic(err.Error())
    }

    fmt.Printf("Found %d pods\n", len(pods.Items))
}
```

### 2. Switching to a Specific Context

To use a different context than the current one:

```go
package main

import (
    "context"
    "fmt"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    // Loading rules for kubeconfig
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()

    // Override to use specific context
    configOverrides := &clientcmd.ConfigOverrides{
        CurrentContext: "prod-admin", // Use this context instead of current-context
    }

    // Create config loader
    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        configOverrides,
    )

    // Get rest.Config
    config, err := kubeConfig.ClientConfig()
    if err != nil {
        panic(err.Error())
    }

    // Create clientset
    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        panic(err.Error())
    }

    fmt.Println("Connected using prod-admin context")
}
```

### 3. Listing All Available Contexts

To see what contexts are available in your kubeconfig:

```go
package main

import (
    "fmt"

    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    // Load kubeconfig
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        &clientcmd.ConfigOverrides{},
    )

    // Get raw config
    rawConfig, err := kubeConfig.RawConfig()
    if err != nil {
        panic(err.Error())
    }

    // List all contexts
    fmt.Println("Available contexts:")
    for name, ctx := range rawConfig.Contexts {
        marker := " "
        if name == rawConfig.CurrentContext {
            marker = "*"
        }
        fmt.Printf("%s %s (cluster: %s, user: %s, namespace: %s)\n",
            marker, name, ctx.Cluster, ctx.AuthInfo, ctx.Namespace)
    }
}
```

### 4. Getting the Namespace from Context

Contexts can specify a default namespace:

```go
package main

import (
    "fmt"

    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        &clientcmd.ConfigOverrides{},
    )

    // Get namespace from context
    namespace, wasSet, err := kubeConfig.Namespace()
    if err != nil {
        panic(err.Error())
    }

    // If context doesn't specify namespace, use default
    if !wasSet {
        namespace = "default"
    }

    fmt.Printf("Using namespace: %s\n", namespace)
}
```

## Advanced Usage

### Overriding Context Settings

You can override any part of the context without modifying kubeconfig:

```go
package main

import (
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
)

func main() {
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()

    // Override multiple settings
    configOverrides := &clientcmd.ConfigOverrides{
        Context: clientcmdapi.Context{
            Cluster:   "production",   // Override cluster
            AuthInfo:  "admin",         // Override user
            Namespace: "kube-system",   // Override namespace
        },
        ClusterInfo: clientcmdapi.Cluster{
            Server: "https://custom-server.com:6443", // Override server URL
        },
        AuthInfo: clientcmdapi.AuthInfo{
            Token: "custom-token", // Override authentication
        },
    }

    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        configOverrides,
    )

    config, err := kubeConfig.ClientConfig()
    if err != nil {
        panic(err.Error())
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        panic(err.Error())
    }

    // clientset now uses all the overrides
}
```

### Using a Custom Kubeconfig File

To load from a different kubeconfig file:

```go
package main

import (
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    // Specify custom kubeconfig path
    loadingRules := &clientcmd.ClientConfigLoadingRules{
        ExplicitPath: "/path/to/custom/kubeconfig",
    }

    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        &clientcmd.ConfigOverrides{},
    )

    config, err := kubeConfig.ClientConfig()
    if err != nil {
        panic(err.Error())
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        panic(err.Error())
    }
}
```

## Complete Example: Context Switcher

Here's a complete example that demonstrates context management:

```go
package main

import (
    "context"
    "fmt"
    "os"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: go run main.go <context-name>")
        listContexts()
        os.Exit(1)
    }

    contextName := os.Args[1]

    // Load kubeconfig
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()

    // Switch to specified context
    configOverrides := &clientcmd.ConfigOverrides{
        CurrentContext: contextName,
    }

    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        configOverrides,
    )

    // Get namespace from context
    namespace, wasSet, err := kubeConfig.Namespace()
    if err != nil {
        panic(err.Error())
    }
    if !wasSet {
        namespace = "default"
    }

    // Create client
    config, err := kubeConfig.ClientConfig()
    if err != nil {
        panic(err.Error())
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        panic(err.Error())
    }

    // Use the client
    fmt.Printf("Using context: %s\n", contextName)
    fmt.Printf("Namespace: %s\n", namespace)

    pods, err := clientset.CoreV1().Pods(namespace).List(context.TODO(), metav1.ListOptions{})
    if err != nil {
        panic(err.Error())
    }

    fmt.Printf("Found %d pods in namespace %s:\n", len(pods.Items), namespace)
    for _, pod := range pods.Items {
        fmt.Printf("  - %s (%s)\n", pod.Name, pod.Status.Phase)
    }
}

func listContexts() {
    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        &clientcmd.ConfigOverrides{},
    )

    rawConfig, err := kubeConfig.RawConfig()
    if err != nil {
        return
    }

    fmt.Println("\nAvailable contexts:")
    for name, ctx := range rawConfig.Contexts {
        marker := " "
        if name == rawConfig.CurrentContext {
            marker = "*"
        }
        ns := ctx.Namespace
        if ns == "" {
            ns = "default"
        }
        fmt.Printf("%s %s (cluster: %s, namespace: %s)\n",
            marker, name, ctx.Cluster, ns)
    }
}
```

## Common Patterns

### Pattern 1: Environment-Based Context Selection

```go
func getClientset() (*kubernetes.Clientset, error) {
    // Use environment variable to select context
    contextName := os.Getenv("KUBE_CONTEXT")
    if contextName == "" {
        contextName = "default"
    }

    loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
    configOverrides := &clientcmd.ConfigOverrides{
        CurrentContext: contextName,
    }

    kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
        loadingRules,
        configOverrides,
    )

    config, err := kubeConfig.ClientConfig()
    if err != nil {
        return nil, err
    }

    return kubernetes.NewForConfig(config)
}
```

### Pattern 2: Multi-Cluster Operations

```go
func getMultiClusterClients(contextNames []string) (map[string]*kubernetes.Clientset, error) {
    clients := make(map[string]*kubernetes.Clientset)

    for _, contextName := range contextNames {
        loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
        configOverrides := &clientcmd.ConfigOverrides{
            CurrentContext: contextName,
        }

        kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
            loadingRules,
            configOverrides,
        )

        config, err := kubeConfig.ClientConfig()
        if err != nil {
            return nil, fmt.Errorf("failed to load context %s: %w", contextName, err)
        }

        clientset, err := kubernetes.NewForConfig(config)
        if err != nil {
            return nil, fmt.Errorf("failed to create client for context %s: %w", contextName, err)
        }

        clients[contextName] = clientset
    }

    return clients, nil
}
```

## API Reference

### Key Types

**ConfigOverrides** - Override kubeconfig settings:
```go
type ConfigOverrides struct {
    AuthInfo       clientcmdapi.AuthInfo  // Override user credentials
    ClusterDefaults clientcmdapi.Cluster  // Default cluster settings
    ClusterInfo    clientcmdapi.Cluster   // Override cluster settings
    Context        clientcmdapi.Context   // Override context settings
    CurrentContext string                 // Override current context
    Timeout        string                 // Override timeout
}
```

**Context** - A context definition:
```go
type Context struct {
    Cluster   string  // Name of the cluster
    AuthInfo  string  // Name of the user (authInfo)
    Namespace string  // Default namespace
}
```

**ClientConfig Interface**:
```go
type ClientConfig interface {
    // Get merged config with all overrides
    RawConfig() (clientcmdapi.Config, error)

    // Get rest.Config for creating clients
    ClientConfig() (*restclient.Config, error)

    // Get namespace from context
    Namespace() (string, bool, error)

    // Get config access rules
    ConfigAccess() ConfigAccess
}
```

## Troubleshooting

### Context Not Found

If you specify a context that doesn't exist:

```go
// This will return an error if context doesn't exist
config, err := kubeConfig.ClientConfig()
if err != nil {
    // Handle error - likely context not found
    fmt.Printf("Error: %v\n", err)
}
```

### Listing Available Contexts for Debug

Always check what contexts are available:

```go
rawConfig, _ := kubeConfig.RawConfig()
fmt.Printf("Current context: %s\n", rawConfig.CurrentContext)
fmt.Printf("Available contexts: %v\n", getContextNames(rawConfig))

func getContextNames(config clientcmdapi.Config) []string {
    names := make([]string, 0, len(config.Contexts))
    for name := range config.Contexts {
        names = append(names, name)
    }
    return names
}
```

## Best Practices

1. **Always handle errors** when loading contexts
2. **Use ConfigOverrides** instead of modifying kubeconfig files
3. **Set namespace fallback** if context doesn't specify one
4. **Use environment variables** for context selection in different environments
5. **Validate context exists** before attempting to use it
6. **Cache clientsets** if working with the same context repeatedly

## See Also

- [client-go documentation](https://pkg.go.dev/k8s.io/client-go)
- [Kubernetes kubeconfig documentation](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [kubectl context commands](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-context-and-configuration)
