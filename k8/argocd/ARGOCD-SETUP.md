# ArgoCD Setup Guide for Artha Helm Chart

This guide provides complete instructions for setting up ArgoCD automation for the `artha-helm-chart` with the application name `demo-helm-app`.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Install ArgoCD](#step-1-install-argocd)
- [Step 2: Access ArgoCD UI](#step-2-access-argocd-ui)
- [Step 3: Configure Git Repository](#step-3-configure-git-repository)
- [Step 4: Deploy the Application](#step-4-deploy-the-application)
- [Step 5: Sync and Monitor](#step-5-sync-and-monitor)
- [GitOps Workflow](#gitops-workflow)
- [Troubleshooting](#troubleshooting)

## Overview

**ArgoCD** is a declarative, GitOps continuous delivery tool for Kubernetes. This setup enables:

- ✅ **GitOps-based deployments**: Git as the single source of truth
- ✅ **Manual sync control**: Explicit approval for deployments
- ✅ **Easy rollbacks**: Revert to previous versions instantly
- ✅ **Visual monitoring**: Web UI for deployment status
- ✅ **Declarative configuration**: Infrastructure as code

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes cluster** running and accessible
2. **kubectl** configured with cluster access
3. **Git repository** containing the artha-helm-chart (public or with access credentials)
4. **Namespace** for applications (default: `default`)
5. **Image registry credentials** configured (if using private registry like helmtest.azurecr.io)

## Step 1: Install ArgoCD

### Option A: Install via kubectl (Recommended)

```bash
# Create argocd namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### Option B: Install via Helm

```bash
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 5.51.0
```

### Verify Installation

```bash
# Check all ArgoCD pods are running
kubectl get pods -n argocd

# Expected output:
# NAME                                  READY   STATUS    RESTARTS
# argocd-application-controller-0       1/1     Running   0
# argocd-dex-server-xxx                 1/1     Running   0
# argocd-redis-xxx                      1/1     Running   0
# argocd-repo-server-xxx                1/1     Running   0
# argocd-server-xxx                     1/1     Running   0
```

## Step 2: Access ArgoCD UI

### Get Initial Admin Password

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Note**: Save this password securely. The default username is `admin`.

### Access Methods

#### Method 1: Port Forward (Quick Access)

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access in browser: https://localhost:8080
# Username: admin
# Password: (from previous command)
```

#### Method 2: LoadBalancer (Production)

```bash
# Change service type to LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get external IP
kubectl get svc argocd-server -n argocd
```

#### Method 3: Ingress (Production)

Create an ingress for ArgoCD (example for nginx-ingress):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
  tls:
    - hosts:
        - argocd.yourdomain.com
      secretName: argocd-tls
```

### Install ArgoCD CLI (Optional but Recommended)

```bash
# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Login to ArgoCD
argocd login localhost:8080 --username admin --password <password> --insecure
```

## Step 3: Configure Git Repository

### For Public Repository

No additional configuration needed. Skip to Step 4.

### For Private Repository

Add your Git repository credentials to ArgoCD:

#### Via UI:
1. Go to **Settings** → **Repositories**
2. Click **Connect Repo**
3. Choose connection method (HTTPS or SSH)
4. Enter repository URL and credentials
5. Click **Connect**

#### Via CLI:

```bash
# For HTTPS with username/password
argocd repo add https://github.com/YOUR-ORG/ingress-to-gatway-api.git \
  --username YOUR_USERNAME \
  --password YOUR_PASSWORD

# For SSH with private key
argocd repo add git@github.com:YOUR-ORG/ingress-to-gatway-api.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

## Step 4: Deploy the Application

### Important: Update Repository URL

Before deploying, update the repository URL in the ArgoCD Application manifest:

```bash
# Edit the ArgoCD Application file
nano argocd/demo-helm-app/argocd-application.yaml

# Update this line to your actual repository URL:
# repoURL: https://github.com/YOUR-ORG/ingress-to-gatway-api.git
```

### Deploy via kubectl

```bash
# Navigate to repository root
cd /home/artha-devops-dhruv/Desktop/Repo's/ingress-to-gatway-api

# Apply the ArgoCD Application manifest
kubectl apply -f argocd/demo-helm-app/argocd-application.yaml

# Verify application is created
kubectl get application -n argocd demo-helm-app
```

### Deploy via ArgoCD CLI

```bash
# Create application from file
argocd app create -f argocd/demo-helm-app/argocd-application.yaml

# Or create directly with parameters
argocd app create demo-helm-app \
  --repo https://github.com/YOUR-ORG/ingress-to-gatway-api.git \
  --path artha-helm-chart \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --helm-set-file valueFiles=application-values.yaml \
  --helm-set-file valueFiles=gateway-values.yaml \
  --helm-set-file valueFiles=../argocd/demo-helm-app/production-values.yaml
```

## Step 5: Sync and Monitor

### Initial Sync

The application is configured with **manual sync**, so you must explicitly trigger deployments.

#### Via UI:
1. Open ArgoCD UI
2. Click on **demo-helm-app** application
3. You'll see status as "OutOfSync"
4. Click **Sync** button
5. Review the resources to be created
6. Click **Synchronize**

#### Via CLI:

```bash
# Sync the application
argocd app sync demo-helm-app

# Sync with prune (remove resources not in Git)
argocd app sync demo-helm-app --prune

# Watch sync progress
argocd app wait demo-helm-app --timeout 300
```

### Monitor Deployment

```bash
# Get application status
argocd app get demo-helm-app

# Watch real-time sync status
watch argocd app get demo-helm-app

# Check deployed resources
kubectl get all -n default | grep demo-helm-app
```

### Check Application Health

```bash
# View application details
argocd app get demo-helm-app

# Expected output should show:
# Health Status: Healthy
# Sync Status: Synced
```

## GitOps Workflow

### Making Changes

1. **Update configuration** in your Git repository:
   ```bash
   # Example: Update image tag in production-values.yaml
   nano argocd/demo-helm-app/production-values.yaml
   
   # Change:
   # applications:
   #   backend:
   #     image:
   #       tag: v1.1.0  # Updated version
   ```

2. **Commit and push** changes:
   ```bash
   git add argocd/demo-helm-app/production-values.yaml
   git commit -m "Update backend to v1.1.0"
   git push origin main
   ```

3. **Sync in ArgoCD**:
   ```bash
   # Via CLI
   argocd app sync demo-helm-app
   
   # Or via UI: Click the application and press "Sync"
   ```

4. **Monitor deployment**:
   ```bash
   argocd app wait demo-helm-app
   ```

### Rollback to Previous Version

#### Via UI:
1. Open application in ArgoCD UI
2. Go to **History and Rollback** tab
3. Select previous successful deployment
4. Click **Rollback**

#### Via CLI:

```bash
# List deployment history
argocd app history demo-helm-app

# Rollback to specific revision (e.g., revision 5)
argocd app rollback demo-helm-app 5

# Rollback to previous revision
argocd app rollback demo-helm-app
```

### Refresh Application

If Git repository has changed but ArgoCD hasn't detected it:

```bash
# Refresh application (re-fetch from Git)
argocd app get demo-helm-app --refresh

# Hard refresh (ignore cache)
argocd app get demo-helm-app --hard-refresh
```

## Troubleshooting

### Application Shows "OutOfSync"

This is expected with manual sync. To deploy changes, trigger a sync:

```bash
argocd app sync demo-helm-app
```

### Application Health is "Progressing"

Wait for the deployment to complete. Monitor with:

```bash
watch argocd app get demo-helm-app
```

### Application Health is "Degraded"

Check the specific resources having issues:

```bash
# Get detailed status
argocd app get demo-helm-app

# Check pods in the namespace
kubectl get pods -n default

# Check specific pod logs
kubectl logs <pod-name> -n default
```

### Sync Failed

View sync errors:

```bash
# Get application details with errors
argocd app get demo-helm-app

# View last sync result
argocd app get demo-helm-app -o yaml | grep -A 20 "status:"
```

Common issues:
- **Image pull errors**: Check registry credentials
- **Resource limits**: Check node capacity
- **Invalid manifests**: Validate with `helm template`

### Cannot Access ArgoCD UI

```bash
# Verify ArgoCD server is running
kubectl get pods -n argocd | grep argocd-server

# Check service
kubectl get svc argocd-server -n argocd

# Restart port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Repository Connection Issues

```bash
# Test repository connectivity
argocd repo list

# For private repos, verify credentials are correct
argocd repo add YOUR_REPO_URL --username USER --password PASS
```

### Helm Template Errors

Test helm rendering locally:

```bash
# Test if helm chart renders correctly
cd /home/artha-devops-dhruv/Desktop/Repo's/ingress-to-gatway-api

helm template demo-helm-app ./artha-helm-chart \
  -f ./artha-helm-chart/application-values.yaml \
  -f ./artha-helm-chart/gateway-values.yaml \
  -f ./argocd/demo-helm-app/production-values.yaml
```

### Delete and Recreate Application

If you need to start fresh:

```bash
# Delete application (resources will be deleted too)
argocd app delete demo-helm-app

# Or delete without removing resources
argocd app delete demo-helm-app --cascade=false

# Recreate
kubectl apply -f argocd/demo-helm-app/argocd-application.yaml
```

## Additional Resources

- [ArgoCD Official Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [ARGOCD-COMMANDS.md](./ARGOCD-COMMANDS.md) - Quick reference for common commands

## Security Best Practices

1. **Change admin password** after initial setup
2. **Enable SSO** for team access (GitHub, GitLab, etc.)
3. **Use RBAC** to control user permissions
4. **Store secrets** in Kubernetes Secrets or external secret managers
5. **Use private Git repositories** for production configurations
6. **Enable audit logging** for compliance
