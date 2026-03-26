# 🤖 Fully Automating External Secrets (Zero YAML Changes)

Right now, your workflow requires two manual steps to add or remove a secret:
1. Update Azure Key Vault.
2. Update the `ExternalSecret` YAML file (`external-secret-backend.yaml`) with a new entry under `spec.data`.

This is standard GitOps practice because it enforces exactly which secrets are pulled. However, if you want **100% full automation** (where you only update Key Vault and ArgoCD/Kubernetes handles the rest automatically), you can use the External Secrets Operator **`dataFrom` pattern**.

## How it works

Instead of explicitly mapping every single secret key in the `ExternalSecret`, you tell ESO to:
1. Fetch **ALL** secrets located inside the connected Key Vault (`find: regexp: ".*"`).
2. Automatically convert the Key Vault's hyphens (`-`) back into environment variable underscores (`_`) on the fly using a `rewrite` rule.

Whenever you add or delete a secret directly in Azure Key Vault, ESO's background controller automatically detects the change within the `refreshInterval` (e.g., 1 minute) and injects the new secret (or removes the deleted one) directly into the Kubernetes Pod.

---

## 🛠️ Step 1: Update your ExternalSecret YAML

You can completely replace your long `external-secret.yaml` files with this short, automated version.

**Example for Backend (`backend/external-secret.yaml`):**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: artha-backend-secrets
  namespace: artha
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: artha-backend-kv-store
    kind: ClusterSecretStore
  
  target:
    name: artha-backend-env-secrets
    creationPolicy: Owner
    
    # Optional: Delete secrets from K8s when they are deleted from Key Vault
    deletionPolicy: Delete

  # ─── THIS IS THE MAGIC PART ───
  dataFrom:
    - find:
        name:
          # This regex ".*" means "fetch every single secret in this Key Vault"
          regexp: ".*"
      
      # Since Azure Key Vault forces us to use hyphens (e.g. DB-HOST), 
      # we rewrite the keys back to underscores (DB_HOST) automatically!
      rewrite:
        - regexp:
            source: "-"
            target: "_"
```

> [!NOTE]
> **Understanding the Name Conversion (The Full Journey)**
> 1. Your `.env` file uses valid Linux names: `DB_HOST`
> 2. `upload-to-keyvault.sh` converts it to `DB-HOST` (because Azure strictly forbids underscores).
> 3. Azure Key Vault safely stores `DB-HOST`.
> 4. The YAML's `rewrite` block (above) grabs `DB-HOST` from Azure and converts it back to `DB_HOST`.
> 5. Your K8s Pod receives `DB_HOST` exactly as your application code expects it!


## 🛠️ Step 2: Push to Git / ArgoCD

1. Replace the contents of your `external-secret.yaml` with the shortened code above.
2. Commit and push it to your `artha-app-gitops` repository.
3. ArgoCD will sync the new file. 

From this point forward, the `spec.data` list is gone from your Git repository.

---

## ⚡ The New Workflow (1-Step Process)

Now, your entire process for adding, updating, or deleting secrets is just a single step:

### ➕ Adding a Secret
1. Go to **Azure Portal → Key Vault** (or run the `az keyvault secret set` command).
2. Create a new secret named `NEW-API-KEY`.
3. **Done.** Within 1 minute, ArgoCD/ESO will automatically pull it, rename it to `NEW_API_KEY`, and inject it into your Kubernetes generic Secret (`artha-backend-env-secrets`).

### 🗑️ Deleting a Secret
1. Go to **Azure Portal → Key Vault** and delete `OLD-API-KEY`.
2. **Done.** Within 1 minute, ESO will automatically strip `OLD_API_KEY` out of your running Kubernetes Cluster.

### 🔄 Pod Restarts (Important Note)
Even though the Kubernetes Secret automatically updates, **your running pods will not auto-restart** by default just because the Secret changed. 

If you want the pods to automatically restart immediately after you add/delete a secret in Key Vault, you should install [Reloader](https://github.com/stakater/Reloader) and add this annotation to your `Deployment`:
```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```
Once Reloader is installed, updating Azure Key Vault will automatically update the Secret, which will automatically trigger a rolling restart of your application pods with the new environment variables!
