# ArgoCD Commands Quick Reference

Quick reference guide for commonly used ArgoCD CLI commands for managing the `demo-helm-app` application.

## Application Management

### Get Application Status

```bash
# Get current status
argocd app get demo-helm-app

# Get status with resource details
argocd app get demo-helm-app --show-operation

# Get status in YAML format
argocd app get demo-helm-app -o yaml

# Get status in JSON format
argocd app get demo-helm-app -o json
```

### List Applications

```bash
# List all applications
argocd app list

# List applications with more details
argocd app list -o wide
```

### Create Application

```bash
# Create from file
argocd app create -f argocd/demo-helm-app/argocd-application.yaml

# Or apply via kubectl
kubectl apply -f argocd/demo-helm-app/argocd-application.yaml
```

### Delete Application

```bash
# Delete application and all resources
argocd app delete demo-helm-app

# Delete application but keep resources in cluster
argocd app delete demo-helm-app --cascade=false

# Delete with confirmation skip
argocd app delete demo-helm-app -y
```

## Sync Operations

### Sync Application

```bash
# Sync application
argocd app sync demo-helm-app

# Sync and wait for completion
argocd app sync demo-helm-app --timeout 300

# Sync with prune (remove resources not in Git)
argocd app sync demo-helm-app --prune

# Dry run sync (preview changes)
argocd app sync demo-helm-app --dry-run

# Sync specific resource
argocd app sync demo-helm-app --resource apps:Deployment:backend
```

### Refresh Application

```bash
# Refresh from Git (soft refresh)
argocd app get demo-helm-app --refresh

# Hard refresh (clear cache)
argocd app get demo-helm-app --hard-refresh
```

### Wait for Sync

```bash
# Wait for sync to complete
argocd app wait demo-helm-app

# Wait with timeout
argocd app wait demo-helm-app --timeout 300

# Wait for health and sync
argocd app wait demo-helm-app --health --sync
```

## Deployment History & Rollback

### View History

```bash
# View deployment history
argocd app history demo-helm-app

# View history with details
argocd app history demo-helm-app -o wide
```

### Rollback

```bash
# Rollback to previous version
argocd app rollback demo-helm-app

# Rollback to specific revision
argocd app rollback demo-helm-app 5

# Rollback with timeout
argocd app rollback demo-helm-app 5 --timeout 300
```

## Diff & Preview

### Show Differences

```bash
# Show diff between Git and cluster
argocd app diff demo-helm-app

# Show diff in compact format
argocd app diff demo-helm-app --compact-diff

# Show diff for specific resource
argocd app diff demo-helm-app --resource apps:Deployment:backend
```

### Show Manifests

```bash
# Show all manifests
argocd app manifests demo-helm-app

# Show manifests and save to file
argocd app manifests demo-helm-app > manifests.yaml
```

## Resource Management

### List Resources

```bash
# List all resources managed by the app
argocd app resources demo-helm-app

# List resources in tree view
argocd app get demo-helm-app --show-operation
```

### Get Resource Details

```bash
# Get specific resource
argocd app get demo-helm-app --resource apps:Deployment:backend

# Get resource logs
argocd app logs demo-helm-app --kind Deployment --name backend

# Follow logs in real-time
argocd app logs demo-helm-app --kind Deployment --name backend --follow
```

### Patch Application

```bash
# Update image tag
argocd app set demo-helm-app \
  --helm-set applications.backend.image.tag=v1.1.0

# Update values file
argocd app set demo-helm-app \
  --values-literal-file production-values.yaml
```

## Repository Management

### List Repositories

```bash
# List all configured repositories
argocd repo list

# List with more details
argocd repo list -o wide
```

### Add Repository

```bash
# Add HTTPS repository with credentials
argocd repo add https://github.com/YOUR-ORG/ingress-to-gatway-api.git \
  --username YOUR_USERNAME \
  --password YOUR_PASSWORD

# Add SSH repository
argocd repo add git@github.com:YOUR-ORG/ingress-to-gatway-api.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

### Remove Repository

```bash
# Remove repository
argocd repo rm https://github.com/YOUR-ORG/ingress-to-gatway-api.git
```

## Monitoring & Debugging

### Watch Application

```bash
# Watch application status
watch argocd app get demo-helm-app

# Watch sync progress
argocd app wait demo-helm-app --timeout 300
```

### View Logs

```bash
# View application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# View repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# View ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Get Events

```bash
# Get application events
argocd app get demo-helm-app -o yaml | grep -A 20 conditions

# Get Kubernetes events
kubectl get events -n default --field-selector involvedObject.name=backend
```

## Login & Authentication

### Login

```bash
# Login with username/password
argocd login localhost:8080 --username admin --password <password> --insecure

# Login with specific server
argocd login argocd.example.com --username admin

# Login and store context
argocd login argocd.example.com --name production-cluster
```

### Logout

```bash
# Logout
argocd logout localhost:8080
```

### Change Password

```bash
# Update admin password
argocd account update-password \
  --account admin \
  --current-password <current> \
  --new-password <new>
```

## Cluster Management

### List Clusters

```bash
# List all configured clusters
argocd cluster list
```

### Add Cluster

```bash
# Add cluster from kubeconfig
argocd cluster add <context-name>
```

## Useful Combinations

### Deploy New Version

```bash
# 1. Update Git repository with new image tag
# 2. Refresh and sync
argocd app get demo-helm-app --refresh
argocd app sync demo-helm-app
argocd app wait demo-helm-app
```

### Complete Health Check

```bash
# Check application, pods, and services
argocd app get demo-helm-app
kubectl get pods -n default -l app.kubernetes.io/instance=demo-helm-app
kubectl get svc -n default
```

### Troubleshoot Failed Sync

```bash
# Get application status
argocd app get demo-helm-app

# View diff
argocd app diff demo-helm-app

# Check pod status
kubectl get pods -n default

# View pod logs
kubectl logs -n default <pod-name>

# Retry sync
argocd app sync demo-helm-app
```

### Full Refresh and Resync

```bash
# Hard refresh from Git
argocd app get demo-helm-app --hard-refresh

# Sync with prune
argocd app sync demo-helm-app --prune

# Wait for completion
argocd app wait demo-helm-app
```

## Environment Variables

Set these for easier command usage:

```bash
# Set ArgoCD server
export ARGOCD_SERVER=localhost:8080

# Set auth token (instead of login)
export ARGOCD_AUTH_TOKEN=<your-token>

# Disable TLS verification (for testing only)
export ARGOCD_OPTS='--insecure'
```

## Common Workflows

### Deploy Production Release

```bash
# 1. Update production-values.yaml with new version
# 2. Commit and push
git add argocd/demo-helm-app/production-values.yaml
git commit -m "Deploy backend v1.1.0 to production"
git push origin main

# 3. Sync application
argocd app sync demo-helm-app --timeout 300

# 4. Verify deployment
argocd app wait demo-helm-app --health
kubectl get pods -n default
```

### Emergency Rollback

```bash
# 1. View history
argocd app history demo-helm-app

# 2. Rollback to last working version
argocd app rollback demo-helm-app

# 3. Verify rollback
argocd app wait demo-helm-app --health
```

### Check Sync Status

```bash
# Quick status check
argocd app get demo-helm-app | grep -E "Health|Sync"

# Full status with resources
argocd app get demo-helm-app
```

## Tips

- Use `--dry-run` to preview changes before applying
- Use `--timeout` to prevent hanging on slow deployments
- Use `--prune` carefully in production (removes resources not in Git)
- Always test in a development environment first
- Use `watch` command for real-time monitoring
- Store frequently used commands as shell aliases

## Additional Resources

- [ARGOCD-SETUP.md](./ARGOCD-SETUP.md) - Complete setup guide
- [ArgoCD CLI Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/)
