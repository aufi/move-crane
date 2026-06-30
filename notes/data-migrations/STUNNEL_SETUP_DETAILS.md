# stunnel Setup: How TLS Tunnel is Established Between Clusters

**Date:** 2026-06-30  
**Purpose:** Detailed explanation of how crane transfer-pvc sets up the TLS tunnel between source and destination clusters

---

## Quick Answer

**stunnel tunnel je nastaven v následujícím pořadí:**

1. **Destination cluster** - vygeneruje self-signed CA certifikát a server/client certifikáty
2. **Destination cluster** - vytvoří stunnel server Pod s certifikáty
3. **Destination → Source** - zkopíruje Secret s certifikáty do source clusteru
4. **Source cluster** - vytvoří stunnel client Pod s těmi samými certifikáty
5. **Source → Destination** - stunnel client se připojí přes Ingress/Route na stunnel server
6. **TLS tunnel** - vzájemná TLS autentizace (mTLS) mezi client a server

---

## Detailed Flow

### Phase 1: Destination Cluster Setup

#### Step 1.1: Create Endpoint (Ingress/Route)

**Kód:** `cmd/transfer-pvc/transfer-pvc.go:323-326`

```go
e, err := createEndpoint(t.Endpoint, destPVC, labels, logger, destClient)
```

**Co se vytvoří:**
- **Ingress** (nginx-ingress) nebo **Route** (OpenShift)
- Exposes external hostname (e.g., `transfer-abc123.apps.cluster.example.com`)
- Backend port: 6443 (stunnel server listen port)

**Example Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: crane-transfer-abc123
  namespace: myapp
spec:
  ingressClassName: nginx
  rules:
  - host: transfer-abc123.apps.cluster.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: stunnel-server-abc123
            port:
              number: 6443
```

#### Step 1.2: Create stunnel Server

**Kód:** `cmd/transfer-pvc/transfer-pvc.go:332-345`

```go
stunnelServer, err := stunneltransport.NewServer(
    context.TODO(),
    destClient,
    logger,
    types.NamespacedName{
        Name:      getValidatedResourceName(destPVC.Name),
        Namespace: destPVC.Namespace,
    }, 
    e,  // endpoint (Ingress/Route)
    &transport.Options{
        Labels: labels,
        Image:  t.Flags.DestinationImage,
    },
)
```

**Co `NewServer` udělá:**

1. **Vygeneruje self-signed certifikáty** (`transport/tls/certs/generate.go`):
   ```go
   crtBundle, err := certs.New()
   // Generates:
   // - CA cert + key (self-signed root CA)
   // - Server cert + key (signed by CA)
   // - Client cert + key (signed by CA)
   ```

2. **Vytvoří Secret s certifikáty**:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: stunnel-certs-abc123
     namespace: myapp
   type: Opaque
   data:
     ca.crt: <base64-encoded CA cert>
     ca.key: <base64-encoded CA key>
     server.crt: <base64-encoded server cert>
     server.key: <base64-encoded server key>
     client.crt: <base64-encoded client cert>
     client.key: <base64-encoded client key>
   ```

3. **Vytvoří ConfigMap se stunnel konfigurací**:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: stunnel-server-config-abc123
     namespace: myapp
   data:
     stunnel.conf: |
       foreground = no
       pid =
       socket = l:TCP_NODELAY=1
       socket = r:TCP_NODELAY=1
       debug = 7
       sslVersion = TLSv1.3
       output=/dev/stdout
       
       # TLS certificates
       key = /etc/stunnel/certs/server.key
       cert = /etc/stunnel/certs/server.crt
       CAfile = /etc/stunnel/certs/ca.crt
       verify = 2  # Require client certificate (mTLS)
       
       [transfer]
       accept = 6443    # Listen port (exposed via Ingress)
       connect = 8080   # Forward to rsync daemon on localhost
       TIMEOUTclose = 0
   ```

4. **Vrátí container spec pro stunnel server**:
   ```yaml
   containers:
   - name: stunnel-server
     image: registry.access.redhat.com/ubi8/ubi:latest
     command: ["/bin/stunnel", "/etc/stunnel/stunnel.conf"]
     ports:
     - containerPort: 6443
       name: tls
     volumeMounts:
     - name: stunnel-config
       mountPath: /etc/stunnel/stunnel.conf
       subPath: stunnel.conf
     - name: stunnel-certs
       mountPath: /etc/stunnel/certs
   
   volumes:
   - name: stunnel-config
     configMap:
       name: stunnel-server-config-abc123
   - name: stunnel-certs
     secret:
       secretName: stunnel-certs-abc123
   ```

**Výsledný Pod v destination clusteru:**
```
┌───────────────────────────────────────┐
│  Pod: rsync-server-abc123             │
│  ┌─────────────────────────────────┐  │
│  │ Container 1: stunnel-server     │  │
│  │ - Listen on :6443 (TLS)         │  │
│  │ - Forward to localhost:8080     │  │
│  │ - Uses server.crt + server.key  │  │
│  │ - Requires client cert (verify=2)│ │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │ Container 2: rsyncd             │  │
│  │ - Listen on localhost:8080      │  │
│  │ - Mounts destination PVC        │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
         ▲
         │ Ingress routes traffic here
         │
┌────────┴──────────┐
│  Ingress          │
│  transfer-abc123  │
│  .apps.cluster... │
└───────────────────┘
```

---

### Phase 2: Copy Certificates to Source Cluster

**Kód:** `cmd/transfer-pvc/transfer-pvc.go:347-373`

```go
// Find certificate secrets in destination cluster
secretList := &corev1.SecretList{}
err = destClient.List(
    context.TODO(),
    secretList,
    client.InNamespace(destPVC.Namespace),
    client.MatchingLabels(labels))

// Copy each secret to source cluster
for i := range secretList.Items {
    destSecret := &secretList.Items[i]
    srcSecret := &corev1.Secret{
        ObjectMeta: metav1.ObjectMeta{
            Name:        destSecret.Name,
            Namespace:   srcPVC.Namespace,
            Labels:      destSecret.Labels,
            Annotations: destSecret.Annotations,
        },
        StringData: destSecret.StringData,
        Data:       destSecret.Data,  // ← TĚ SAMÉ certifikáty!
    }
    err = srcClient.Create(context.TODO(), srcSecret)
}
```

**KRITICKÉ:** Source cluster dostane **STEJNÉ certifikáty** jako destination cluster!

To umožňuje:
- Mutual TLS (mTLS) authentication
- Client cert je podepsaný stejným CA jako server cert
- Server může ověřit client cert pomocí CA cert
- Client může ověřit server cert pomocí CA cert

---

### Phase 3: Source Cluster Setup

#### Step 3.1: Create stunnel Client

**Kód:** `cmd/transfer-pvc/transfer-pvc.go:375-389`

```go
stunnelClient, err := stunneltransport.NewClient(
    context.TODO(),
    srcClient,
    logger,
    types.NamespacedName{
        Name:      getValidatedResourceName(srcPVC.Name),
        Namespace: srcPVC.Namespace,
    }, 
    e.Hostname(),  // Ingress hostname from destination
    e.IngressPort(),  // Port 6443
    &transport.Options{
        Labels: labels,
        Image:  t.Flags.DestinationImage,
    },
)
```

**Co `NewClient` udělá:**

1. **Najde existující Secret s certifikáty** (zkopírované z destination):
   ```go
   // Secret už existuje v source namespace (zkopírovaný v Phase 2)
   secretRef := types.NamespacedName{
       Name:      "stunnel-certs-abc123",
       Namespace: srcPVC.Namespace,
   }
   ```

2. **Vytvoří ConfigMap se stunnel client konfigurací**:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: stunnel-client-config-abc123
     namespace: myapp
   data:
     stunnel.conf: |
       pid =
       sslVersion = TLSv1.3
       client = yes  # Client mode
       syslog = no
       output = /dev/stdout
       
       # TLS certificates (STEJNÉ jako na server!)
       key = /etc/stunnel/certs/client.key
       cert = /etc/stunnel/certs/client.crt
       CAfile = /etc/stunnel/certs/ca.crt
       verify = 2  # Verify server certificate
       
       [transfer]
       debug = 7
       accept = 6443  # Local port for rsync to connect to
       connect = transfer-abc123.apps.cluster.example.com:443
       # ↑ Destination Ingress hostname
   ```

3. **Vrátí container spec pro stunnel client**:
   ```yaml
   containers:
   - name: stunnel-client
     image: registry.access.redhat.com/ubi8/ubi:latest
     command: ["/bin/stunnel", "/etc/stunnel/stunnel.conf"]
     volumeMounts:
     - name: stunnel-config
       mountPath: /etc/stunnel/stunnel.conf
       subPath: stunnel.conf
     - name: stunnel-certs
       mountPath: /etc/stunnel/certs
   
   volumes:
   - name: stunnel-config
     configMap:
       name: stunnel-client-config-abc123
   - name: stunnel-certs
     secret:
       secretName: stunnel-certs-abc123  # ← Zkopírované certifikáty!
   ```

**Výsledný Pod v source clusteru:**
```
┌───────────────────────────────────────┐
│  Pod: rsync-client-abc123             │
│  ┌─────────────────────────────────┐  │
│  │ Container 1: stunnel-client     │  │
│  │ - Listen on localhost:6443      │  │
│  │ - Connect to destination Ingress│  │
│  │ - Uses client.crt + client.key  │  │
│  │ - Verifies server cert (verify=2)│ │
│  └─────────────────────────────────┘  │
│  ┌─────────────────────────────────┐  │
│  │ Container 2: rsync              │  │
│  │ - Connects to localhost:6443    │  │
│  │ - Mounts source PVC (read-only) │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

---

### Phase 4: TLS Tunnel Establishment

#### Connection Flow:

```
Source Cluster                         Internet                    Destination Cluster
┌──────────────────┐                                              ┌──────────────────┐
│  rsync-client    │                                              │  rsync-server    │
│  ┌────────────┐  │                                              │  ┌────────────┐  │
│  │   rsync    │  │                                              │  │  rsyncd    │  │
│  │  client    │  │                                              │  │  daemon    │  │
│  └─────┬──────┘  │                                              │  └──────▲─────┘  │
│        │         │                                              │         │        │
│   connect to     │                                              │    listening     │
│  localhost:6443  │                                              │  localhost:8080  │
│        │         │                                              │         │        │
│        ▼         │                                              │         │        │
│  ┌────────────┐  │    TLS Handshake (mTLS)                     │  ┌──────┴─────┐  │
│  │  stunnel   │──┼──────────────────────────────────────────┬──┼─▶│  stunnel   │  │
│  │  client    │  │                                           │  │  │  server    │  │
│  └────────────┘  │                                           │  │  └────────────┘  │
│  - client.crt    │  1. ClientHello                           │  │  - server.crt    │
│  - client.key    │  ──────────────────────────────────────▶  │  │  - server.key    │
│  - ca.crt        │                                           │  │  - ca.crt        │
│                  │  2. ServerHello + server.crt              │  │                  │
│                  │  ◀──────────────────────────────────────  │  │                  │
│                  │     Client verifies server.crt            │  │                  │
│                  │     using ca.crt ✓                        │  │                  │
│                  │                                           │  │                  │
│                  │  3. Client sends client.crt               │  │                  │
│                  │  ──────────────────────────────────────▶  │  │                  │
│                  │                                           │  │  Server verifies │
│                  │                                           │  │  client.crt      │
│                  │                                           │  │  using ca.crt ✓  │
│                  │                                           │  │                  │
│                  │  4. Encrypted TLS tunnel established      │  │                  │
│                  │  ◀═══════════════════════════════════════▶│  │                  │
└──────────────────┘                                           │  └──────────────────┘
                                                                │
                                                                │
                                                     ┌──────────┴───────────┐
                                                     │  Ingress/Route       │
                                                     │  transfer-abc123...  │
                                                     │  - TLS passthrough   │
                                                     │  - Or TLS termination│
                                                     │    at Ingress, then  │
                                                     │    re-encrypt to Pod │
                                                     └──────────────────────┘
```

#### TLS Handshake Details:

1. **Client → Server: ClientHello**
   - TLS version: 1.3
   - Cipher suites supported

2. **Server → Client: ServerHello + Certificate**
   - Server sends `server.crt`
   - Client verifies `server.crt` is signed by `ca.crt` ✓

3. **Client → Server: Client Certificate**
   - Server requests client certificate (`verify = 2`)
   - Client sends `client.crt`
   - Server verifies `client.crt` is signed by `ca.crt` ✓

4. **Both: Session Keys Exchange**
   - Encrypted symmetric keys for tunnel
   - TLS tunnel established ✓

5. **Data Transfer:**
   ```
   rsync client → localhost:6443 (plaintext) → stunnel client → 
   TLS tunnel (encrypted) → stunnel server → localhost:8080 (plaintext) → 
   rsyncd daemon → destination PVC
   ```

---

## Key Security Features

### 1. **Mutual TLS (mTLS)**
- Both client and server authenticate each other
- `verify = 2` means "require and verify peer certificate"
- Prevents man-in-the-middle attacks

### 2. **Self-Signed CA**
- Generated fresh for each transfer
- Not tied to any external CA
- Certificates are ephemeral (deleted after transfer)

### 3. **Certificate Distribution**
- Certificates generated in destination cluster
- Copied to source cluster via Kubernetes API
- No manual certificate management

### 4. **TLS 1.3**
- Modern TLS version (`sslVersion = TLSv1.3`)
- Strong cipher suites
- Forward secrecy

### 5. **TCP Optimizations**
- `TCP_NODELAY=1` disables Nagle's algorithm
- Reduces latency for small packets
- Important for rsync delta-transfer algorithm

---

## Configuration Files

### stunnel Server Config (`/etc/stunnel/stunnel.conf`)

```ini
foreground = no
pid =
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
debug = 7
sslVersion = TLSv1.3
output=/dev/stdout

# Server certificates
key = /etc/stunnel/certs/server.key
cert = /etc/stunnel/certs/server.crt
CAfile = /etc/stunnel/certs/ca.crt
verify = 2  # Require client cert

[transfer]
accept = 6443    # External port (Ingress listens here)
connect = 8080   # Forward to rsyncd on localhost
TIMEOUTclose = 0
```

### stunnel Client Config (`/etc/stunnel/stunnel.conf`)

```ini
pid =
sslVersion = TLSv1.3
client = yes  # Client mode
syslog = no
output = /dev/stdout

# Client certificates
key = /etc/stunnel/certs/client.key
cert = /etc/stunnel/certs/client.crt
CAfile = /etc/stunnel/certs/ca.crt
verify = 2  # Verify server cert

[transfer]
debug = 7
accept = 6443  # Local port for rsync to connect to
connect = transfer-abc123.apps.cluster.example.com:443
```

---

## Alternative: PSK (Pre-Shared Key) Mode

stunnel also supports PSK mode (not mTLS):

```ini
# Server
ciphers = PSK
PSKsecrets = /etc/stunnel/certs/key

# Client
ciphers = PSK
PSKsecrets = /etc/stunnel/certs/key
```

**Not used by default** - crane uses TLS certificate mode.

---

## Troubleshooting

### Check stunnel Server Logs:

```bash
kubectl logs -n myapp rsync-server-abc123 -c stunnel-server

# Expected output:
# LOG5[0]: Service [transfer] accepted connection from 10.0.0.1:12345
# LOG5[0]: s_connect: connected 127.0.0.1:8080
# LOG5[0]: Service [transfer] connected remote server from 127.0.0.1:6789
```

### Check stunnel Client Logs:

```bash
kubectl logs -n myapp rsync-client-abc123 -c stunnel-client

# Expected output:
# LOG5[0]: Service [transfer] accepted connection from 127.0.0.1:12345
# LOG5[0]: s_connect: connected transfer-abc123.apps.cluster.example.com:443
# LOG5[0]: Certificate accepted at depth=0: CN=cert.backube.dev
```

### Verify Certificate Secret:

```bash
kubectl get secret -n myapp stunnel-certs-abc123 -o yaml

# Should contain:
# data:
#   ca.crt: <base64>
#   ca.key: <base64>
#   server.crt: <base64>
#   server.key: <base64>
#   client.crt: <base64>
#   client.key: <base64>
```

### Test Certificate Validity:

```bash
# Extract CA cert
kubectl get secret -n myapp stunnel-certs-abc123 \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Extract server cert
kubectl get secret -n myapp stunnel-certs-abc123 \
  -o jsonpath='{.data.server\.crt}' | base64 -d > server.crt

# Verify server cert is signed by CA
openssl verify -CAfile ca.crt server.crt
# Output: server.crt: OK
```

---

## Summary

**Kde se nastavuje tunnel:**

1. **Destination cluster** - `stunneltransport.NewServer()` vygeneruje certifikáty
2. **Destination → Source** - crane zkopíruje Secret s certifikáty
3. **Source cluster** - `stunneltransport.NewClient()` použije zkopírované certifikáty
4. **Runtime** - stunnel containery establují TLS tunnel při startu Podů

**Klíčové poznatky:**
- ✅ **Certifikáty se generují v destination clusteru** (backube/pvc-transfer/transport/tls/certs)
- ✅ **Stejné certifikáty se kopírují do source clusteru** (crane to dělá automaticky)
- ✅ **Mutual TLS (mTLS)** - obě strany se autentizují certifikáty
- ✅ **Self-signed CA** - žádná external CA není potřeba
- ✅ **Ephemeral certificates** - generované pro každý transfer, pak smazané

**Pro rclone:**
- rclone má **built-in HTTPS support** - nepotřebuje stunnel!
- rclone může přímo používat TLS (`--use-server-modtime --cert client.crt --key client.key`)
- Jednodušší architektura (bez extra stunnel containerů)

