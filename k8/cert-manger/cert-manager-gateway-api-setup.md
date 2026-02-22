# Cert-Manager Setup with Kubernetes Gateway API

This document covers the complete setup of cert-manager for automatic TLS certificate management with Kubernetes Gateway API.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Fresh cert-manager Installation](#fresh-cert-manager-installation)
3. [ClusterIssuer Configuration](#clusterissuer-configuration)
4. [Gateway Integration](#gateway-integration)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Kubernetes cluster (1.25+)
- kubectl configured
- Helm 3.x installed
- Gateway API CRDs installed
- A Gateway controller (e.g., Nginx Gateway Fabric)

---

## Fresh cert-manager Installation

### Step 1: Add Jetstack Helm Repository

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Step 2: Install cert-manager with Gateway API Support

```bash
# Install cert-manager with Gateway API feature enabled
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set crds.enabled=true \
  --set featureGates="ExperimentalGatewayAPISupport=true" \
  --set extraArgs="{--enable-gateway-api}"
```

### Step 3: Verify Installation

```bash
# Check pods are running
kubectl get pods -n cert-manager

# Check cert-manager has Gateway API flag
kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n'
```

**Expected output should include:** `--enable-gateway-api`

---

## ClusterIssuer Configuration

### Create Gateway API ClusterIssuer

Create file `clusterIssuer-gateway.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-gateway
spec:
  acme:
    # Your email for Let's Encrypt notifications
    email: your-email@example.com
    # Production ACME server
    server: https://acme-v02.api.letsencrypt.org/directory
    # Secret to store ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod-gateway
    solvers:
    - http01:
        # Use Gateway API HTTP-01 solver (NOT ingress)
        gatewayHTTPRoute:
          parentRefs:
          - name: nginx-gateway        # Your Gateway name
            namespace: nginx-gateway   # Your Gateway namespace
            kind: Gateway
```

### Apply the ClusterIssuer

```bash
kubectl apply -f clusterIssuer-gateway.yaml
```

### Verify ClusterIssuer is Ready

```bash
kubectl get clusterissuer letsencrypt-prod-gateway
```

**Expected output:**
```
NAME                        READY   AGE
letsencrypt-prod-gateway    True    1m
```

---

## Gateway Integration

### Option A: Automatic Certificates via Gateway Annotation

Add annotation to your Gateway to automatically create certificates:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: nginx-gateway
  namespace: nginx-gateway
  annotations:
    # This triggers automatic certificate creation
    cert-manager.io/cluster-issuer: letsencrypt-prod-gateway
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  # HTTPS listener - cert-manager will auto-create certificate
  - name: https-example-com
    port: 443
    protocol: HTTPS
    hostname: example.com
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: example-com-tls  # cert-manager creates this
    allowedRoutes:
      namespaces:
        from: All
```

### Option B: Manual Certificate Creation

Create Certificate resource manually:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-tls
  namespace: nginx-gateway
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-prod-gateway
    kind: ClusterIssuer
  dnsNames:
  - example.com
  - www.example.com
```

---

## Verification

### Check Certificates

```bash
# List all certificates
kubectl get certificates -A

# Describe a specific certificate
kubectl describe certificate <cert-name> -n <namespace>
```

### Check Challenges (During Issuance)

```bash
# List challenges
kubectl get challenges -A

# Describe challenge for debugging
kubectl describe challenge <challenge-name> -n <namespace>
```

### Check HTTPRoute Created by cert-manager

When a challenge is in progress, cert-manager creates a temporary HTTPRoute:

```bash
kubectl get httproutes -A | grep -i acme
```

---

## Troubleshooting

### Issue: Challenge stuck with 404 error

**Cause:** No HTTPRoute for ACME challenge on HTTP listener.

**Solution:**
1. Ensure `--enable-gateway-api` flag is set on cert-manager
2. Ensure ClusterIssuer uses `gatewayHTTPRoute` (not `ingress`)
3. Ensure DNS points directly to Gateway IP (not through proxy)

### Issue: Challenge stuck with 409 error

**Cause:** DNS goes through Cloudflare or other proxy.

**Solution:**
1. Set DNS to "DNS Only" mode (grey cloud in Cloudflare)
2. Or use DNS-01 challenge instead of HTTP-01

### Issue: ClusterIssuer not ready

**Check logs:**
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

### Issue: Certificates not auto-created from Gateway annotation

**Ensure:**
1. cert-manager has `--enable-gateway-api` flag
2. Gateway has `cert-manager.io/cluster-issuer` annotation
3. HTTPS listeners have proper `tls.certificateRefs`

---

## Quick Reference

| Component | Value |
|-----------|-------|
| ClusterIssuer Name | `letsencrypt-prod-gateway` |
| Solver Type | `http01.gatewayHTTPRoute` |
| cert-manager Flag | `--enable-gateway-api` |
| Gateway Annotation | `cert-manager.io/cluster-issuer: letsencrypt-prod-gateway` |

---

## Files Reference

- **ClusterIssuer:** `clusterIssuer-gateway.yaml`
- **Gateway Values:** `artha-helm-chart/gateway-values.yaml`
