# ArgoCD Image Updater Setup Guide

Quick setup guide for ArgoCD Image Updater v1.0.2+ (CR-based approach).

## Prerequisites

- ArgoCD installed in `argocd` namespace
- ArgoCD Application deployed
- ACR (Azure Container Registry) with images

---

## Step 1: Install Image Updater

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/config/install.yaml
```

Verify:
```bash
kubectl get pods -n argocd | grep image-updater
```

---

## Step 2: Create Secrets

### ACR Credentials
```bash
kubectl create secret docker-registry acr-credentials \
  --namespace argocd \
  --docker-server=helmtest.azurecr.io \
  --docker-username=<ACR_USERNAME> \
  --docker-password=<ACR_PASSWORD>
```

### Git Credentials (for write-back)
```bash
kubectl create secret generic git-creds \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=<GITLAB_USERNAME> \
  --from-literal=username=<GITLAB_USERNAME> \
  --from-literal=password=<GItlab_PAT>
```
> **Note:** GITLAB PAT needs `repo` scope.

#### Assign Label to this crated secray so argocd git repo server
```bash
kubectl label secret git-creds \
  -n argocd \
  argocd.argoproj.io/secret-type=repository
```

#### Restart repo-server
```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```



---

## Step 3: Create ImageUpdater CR

Create `image-updater.yaml`:

```yaml
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: demo-artha-app-updater
  namespace: argocd
spec:
  namespace: argocd
  
  commonUpdateSettings:
    updateStrategy: "newest-build"  # or "semver", "latest", "digest"
  
  writeBackConfig:
    method: "git:secret:argocd/git-creds"
    gitConfig:
      branch: "master"
      writeBackTarget: "helmvalues:application-values.yaml"
  
  applicationRefs:
    - namePattern: "demo-artha-app"
      images:
        - alias: "backend"
          imageName: "helmtest.azurecr.io/arthanode"
          commonUpdateSettings:
            pullSecret: "pullsecret:argocd/acr-credentials"
          manifestTargets:
            helm:
              name: "applications.backend.image.repository"
              tag: "applications.backend.image.tag"
```

Apply:
```bash
kubectl apply -f image-updater.yaml
```

---

## Step 4: Verify

Check logs:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

Test by pushing a new image:
```bash
docker push helmtest.azurecr.io/arthanode:v1.0.1
```

Within 2 minutes, Image Updater will:
1. Detect the new image
2. Commit update to Git
3. ArgoCD shows "OutOfSync"
4. Manually sync to deploy

---

## Update Strategies

| Strategy | Description |
|----------|-------------|
| `semver` | Follows semantic versioning (v1.0.0) |
| `latest` | Tracks newest tag alphabetically |
| `newest-build` | Tracks by build timestamp |
| `digest` | Tracks image digest changes |

---

## Troubleshooting

```bash
# Check Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=50

# Check secrets exist
kubectl get secrets -n argocd | grep -E "acr-credentials|git-creds"

# Check ImageUpdater CR status
kubectl get imageupdaters -n argocd
```
