# AKS External Secrets Manager with Azure Key Vault — Complete Setup Guide

> **Goal**: Remove all secrets from Dockerfiles / `.env` files for **3 deployments (Admin, Frontend, Backend)** and manage them securely via **3 separate Azure Key Vaults** + **External Secrets Operator (ESO)** on AKS.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Step 1 — Create 3 Azure Key Vaults (Portal)](#3-step-1--create-3-azure-key-vaults)
4. [Step 2 — Upload Secrets to Each Key Vault (Portal)](#4-step-2--upload-secrets-to-each-key-vault)
5. [Step 3 — Enable Workload Identity on AKS (Portal)](#5-step-3--enable-workload-identity-on-aks)
6. [Step 4 — Create 3 Managed Identities (Portal)](#6-step-4--create-3-managed-identities)
7. [Step 5 — Create Federated Credentials (Portal)](#7-step-5--create-federated-credentials)
8. [Step 6 — Grant Key Vault Access to Identities (Portal)](#8-step-6--grant-key-vault-access)
9. [Step 7 — Install External Secrets Operator (Helm)](#9-step-7--install-external-secrets-operator)
10. [Step 8 — Create Kubernetes Service Accounts](#10-step-8--create-kubernetes-service-accounts)
11. [Step 9 — Create 3 ClusterSecretStores](#11-step-9--create-3-clustersecretstores)
12. [Step 10 — Create 3 ExternalSecrets](#12-step-10--create-3-externalsecrets)
13. [Step 11 — Use Secrets in Deployments](#13-step-11--use-secrets-in-deployments)
14. [Step 12 — Remove Secrets from Dockerfile](#14-step-12--remove-secrets-from-dockerfile)
15. [Day-2 Operations: Add / Update / Remove Secrets](#15-day-2-operations)
16. [Verification & Troubleshooting](#16-verification--troubleshooting)
17. [Security Best Practices](#17-security-best-practices)
18. [Auto-Generate ExternalSecret YAML (Script)](#18-auto-generate-externalsecret-yaml)

---

## Architecture Overview

```
  ┌──────────────────┐    ┌───────────────────┐    ┌──────────────────┐
  │  Key Vault:       │    │  Key Vault:        │    │  Key Vault:       │
  │  admin-kv         │    │  frontend-kv       │    │  backend-kv       │
  │                   │    │                    │    │                   │
  │  DB-HOST          │    │  API-URL           │    │  DB-HOST          │
  │  JWT-SECRET       │    │  GA-ID             │    │  DB-PASSWORD      │
  │  ADMIN-API-KEY    │    │  SENTRY-DSN        │    │  REDIS-URL        │
  │  ...              │    │  ...               │    │  JWT-SECRET       │
  └────────┬──────────┘    └────────┬───────────┘    │  SMTP-HOST        │
           │                        │                │  ...              │
           │   Workload Identity    │                └────────┬──────────┘
           │   (OIDC Federation)    │                         │
  ┌────────▼────────────────────────▼─────────────────────────▼──────────┐
  │                    External Secrets Operator (ESO)                    │
  │                    (runs inside AKS cluster)                          │
  └──────┬─────────────────────┬──────────────────────────┬──────────────┘
         │                     │                          │
    ClusterSecretStore    ClusterSecretStore         ClusterSecretStore
    (admin-kv-store)      (frontend-kv-store)        (backend-kv-store)
         │                     │                          │
    ExternalSecret        ExternalSecret             ExternalSecret
         │                     │                          │
         ▼                     ▼                          ▼
    K8s Secret             K8s Secret                K8s Secret
    admin-env-secrets      frontend-env-secrets      backend-env-secrets
         │                     │                          │
         ▼                     ▼                          ▼
    ┌─────────┐          ┌──────────┐              ┌─────────┐
    │ Admin   │          │ Frontend │              │ Backend │
    │ Deploy  │          │ Deploy   │              │ Deploy  │
    └─────────┘          └──────────┘              └─────────┘
```

**How it works:**
1. Each app has its **own dedicated Key Vault** for complete isolation.
2. Each Key Vault has its **own Managed Identity** with federated credentials.
3. ESO creates **3 separate Kubernetes Secrets** — one per deployment.
4. Each Deployment reads its own Secret via `envFrom` — **zero secrets in Dockerfiles**.

---

## Prerequisites

| Requirement | How to Verify |
|---|---|
| Azure subscription with Owner/Contributor access | Portal → Subscriptions → check your role |
| AKS cluster running | Portal → Kubernetes services → verify cluster is running |
| kubectl configured for AKS | Run `kubectl get nodes` in terminal |
| Helm ≥ 3.x installed | Run `helm version` in terminal |

---

## Step 1 — Create 3 Azure Key Vaults

You need to create this step **3 times** — once for each app.

### Portal Steps

1. Go to [portal.azure.com](https://portal.azure.com)
2. Search **"Key vaults"** in the top search bar → Click **"Key vaults"**
3. Click **"+ Create"**

#### Basics Tab

| Field | Admin Vault | Frontend Vault | Backend Vault |
|---|---|---|---|
| **Subscription** | Your subscription | Your subscription | Your subscription |
| **Resource group** | `your-rg-name` | `your-rg-name` | `your-rg-name` |
| **Key vault name** | `admin-kv` | `frontend-kv` | `backend-kv` |
| **Region** | `Central India` | `Central India` | `Central India` |
| **Pricing tier** | `Standard` | `Standard` | `Standard` |

> [!IMPORTANT]
> - Key Vault names must be **globally unique** across all of Azure (3–24 characters, alphanumeric + hyphens only).
> - Choose the **same region** as your AKS cluster to minimize latency.
> - **Standard tier** is sufficient for secrets. Premium adds HSM-backed keys (not needed here).

4. Click **"Next: Access configuration"**

#### Access Configuration Tab

| Field | Value | Explanation |
|---|---|---|
| **Permission model** | **Azure role-based access control (RBAC)** | RBAC is the recommended model. It uses Azure IAM roles instead of legacy "Access Policies". It's more granular, auditable, and consistent with how the rest of Azure works. |

> [!NOTE]
> **Why RBAC over Access Policies?**
> - Access Policies are the older model — attached directly to the Key Vault.
> - RBAC uses Azure IAM, the same system used for all other Azure resources.
> - RBAC supports conditions, PIM (privileged identity management), and is easier to audit.
> - Microsoft recommends RBAC for all new Key Vaults.

5. Click **"Next: Networking"**

#### Networking Tab

| Field | Value | Explanation |
|---|---|---|
| **Network access** | `Allow public access from all networks` | We'll start with public access for initial setup. You can restrict to AKS VNET later (covered in Security Best Practices). |

6. Click **"Review + create"** → **"Create"**
7. Wait for deployment → Click **"Go to resource"**
8. Note the **Vault URI** from the Overview page (e.g., `https://admin-kv.vault.azure.net`)

**Repeat steps 3–8 for all 3 vaults.**

### After Creation — What You Should See

In Portal → Key vaults, you should see:

| Key Vault Name | Vault URI | Region |
|---|---|---|
| `admin-kv` | `https://admin-kv.vault.azure.net` | Central India |
| `frontend-kv` | `https://frontend-kv.vault.azure.net` | Central India |
| `backend-kv` | `https://backend-kv.vault.azure.net` | Central India |

---

## Step 2 — Upload Secrets to Each Key Vault

Upload each app's secrets to its respective Key Vault. You can do this manually via the Portal (for a few secrets) or use the provided script (recommended for 50+ secrets).

### Option A: Use the Upload Script (Recommended)

To run the upload script, you must first grant yourself the **Key Vault Secrets Officer** role in the portal.

**Portal Steps (Assign RBAC Role to Yourself):**
1.  Go to the [Azure Portal](https://portal.azure.com).
2.  Navigate to your Key Vault (e.g., `backend-kv`).
3.  In the left sidebar, click **Access control (IAM)**.
4.  Click **+ Add** → **Add role assignment**.
5.  **Role Tab**: Search for **Key Vault Secrets Officer** and select it.
6.  **Members Tab**:
    *   **Assign access to**: User, group, or service principal.
    *   **+ Select members**: Search for your email/account (the one logged in via `az login`).
7.  Click **Review + assign**.

> [!IMPORTANT]
> **Wait 2–5 minutes** for the role to propagate before running the script below.

**Usage:**
```bash
# 1. Login to Azure (mandatory)
az login

# 2. Make the script executable
chmod +x upload-to-keyvault.sh

# 3. Run for each app (Admin, Frontend, Backend)
./upload-to-keyvault.sh admin.env    admin-kv
./upload-to-keyvault.sh frontend.env frontend-kv
./upload-to-keyvault.sh backend.env  backend-kv
```



> [!TIP]
> **Dry Run Mode**: To see what will be uploaded without making any changes, run:
> `DRY_RUN=true ./upload-to-keyvault.sh backend.env backend-kv`

### Option B: Portal Steps (Manual)

1. Go to **Key vaults** → Click the vault (e.g., `backend-kv`)
2. In the left sidebar under **"Objects"** → Click **"Secrets"**
3. Click **"+ Generate/Import"**
4. Fill in:

   | Field | Value | Explanation |
   |---|---|---|
   | **Upload options** | `Manual` | We're manually entering the secret |
   | **Name** | `DB-PASSWORD` | The secret identifier. **Must use hyphens, not underscores.** Azure Key Vault does NOT allow underscores in names. So `DB_PASSWORD` becomes `DB-PASSWORD`. |
   | **Secret value** | `SuperSecret123!` | The actual secret value |
   | **Content type** | Leave blank or `text/plain` | Optional metadata describing the value type |
   | **Set activation date** | Optional | Date from which the secret becomes active |
   | **Set expiration date** | Optional | Date after which the secret expires (useful for rotatable secrets) |
   | **Enabled** | `Yes` | Whether the secret is currently active |

5. Click **"Create"**
6. **Repeat for every secret in that app's `.env` file**

> [!WARNING]
> **Underscore Rule**: Key Vault secret names do **NOT** allow underscores (`_`). You must convert them to hyphens (`-`):
> - `DB_HOST` → `DB-HOST`
> - `JWT_SECRET` → `JWT-SECRET`
> - `SMTP_PASSWORD` → `SMTP-PASSWORD`
> - `AWS_ACCESS_KEY_ID` → `AWS-ACCESS-KEY-ID`
>
> The ExternalSecret manifest (Step 10) will map them back to underscores for your app.

### Example: What Each Vault Should Contain

**admin-kv** (Secrets):
| Secret Name | Example Value |
|---|---|
| `DB-HOST` | `admin-db.postgres.database.azure.com` |
| `DB-PORT` | `5432` |
| `DB-USER` | `admin_user` |
| `DB-PASSWORD` | `AdminPass123!` |
| `JWT-SECRET` | `admin-jwt-key-xxx` |
| `ADMIN-API-KEY` | `ak_live_xxx` |

**frontend-kv** (Secrets):
| Secret Name | Example Value |
|---|---|
| `API-URL` | `https://api.yourdomain.com` |
| `GA-ID` | `G-XXXXXXXXXX` |
| `SENTRY-DSN` | `https://xxx@sentry.io/xxx` |
| `NEXT-PUBLIC-API-URL` | `https://api.yourdomain.com` |

**backend-kv** (Secrets):
| Secret Name | Example Value |
|---|---|
| `DB-HOST` | `backend-db.postgres.database.azure.com` |
| `DB-PORT` | `5432` |
| `DB-USER` | `backend_user` |
| `DB-PASSWORD` | `BackendPass456!` |
| `REDIS-URL` | `redis://redis-host:6379` |
| `JWT-SECRET` | `backend-jwt-key-xxx` |
| `SMTP-HOST` | `smtp.zeptomail.com` |
| `SMTP-PASSWORD` | `smtp-api-key` |

### Verify

For each vault: Click on any secret → Click the **current version** → Click **"Show Secret Value"** → Confirm the value is correct.

---

## Step 3 — Enable Workload Identity on AKS

> [!NOTE]
> **What is Workload Identity?**
> Normally, if a pod needs to access an Azure service (like Key Vault), you'd need to store Azure credentials in the cluster — which is insecure. Workload Identity eliminates this by creating a trust relationship between your Kubernetes Service Account and an Azure Managed Identity using OIDC (OpenID Connect). The pod gets a token automatically — no credentials stored anywhere.

### Portal Steps

1. Go to **Kubernetes services** → Click your AKS cluster
2. In the left sidebar, click **"Security configuration"** (under Settings)
3. Find **"OIDC Issuer"**:
   - Toggle to **Enabled**
   - **Explanation**: OIDC Issuer makes your AKS cluster an OpenID Connect token issuer. Azure AD trusts tokens from this issuer, allowing pods to authenticate as Azure identities.

4. Find **"Workload Identity"**:
   - Toggle to **Enabled**
   - **Explanation**: This installs a webhook in your cluster that automatically injects identity tokens into pods that use annotated Service Accounts.

5. Click **"Save"** (takes 2–3 minutes to apply)

6. After saving, note the **OIDC Issuer URL** displayed on the page.
   - It looks like: `https://centralindia.oic.prod-aks.azure.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/`
   - **Copy this URL** — you need it in Step 5.

---

## Step 4 — Create 3 Managed Identities

Each Key Vault gets its own Managed Identity. This gives each app isolated, independent access.

> [!NOTE]
> **What is a Managed Identity?**
> It's an Azure AD identity that your application uses to authenticate to Azure services. Unlike a Service Principal, you don't manage passwords or certificates — Azure handles everything. It's like giving your app a secure "ID card" that Azure auto-rotates.

### Portal Steps

1. Search **"Managed Identities"** in the top search bar → Click it
2. Click **"+ Create"**
3. Fill in:

| Field | Admin Identity | Frontend Identity | Backend Identity |
|---|---|---|---|
| **Subscription** | Your subscription | Your subscription | Your subscription |
| **Resource group** | `your-rg-name` | `your-rg-name` | `your-rg-name` |
| **Region** | `Central India` | `Central India` | `Central India` |
| **Name** | `admin-eso-identity` | `frontend-eso-identity` | `backend-eso-identity` |

4. Click **"Review + create"** → **"Create"**
5. After creation, go to the identity → **Overview** page
6. **Copy the "Client ID"** — you need it in Steps 5 and 8.

**Repeat for all 3 identities.**

### After Creation — What You Should Have

| Managed Identity Name | Client ID (example) |
|---|---|
| `admin-eso-identity` | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` |
| `frontend-eso-identity` | `bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb` |
| `backend-eso-identity` | `cccccccc-cccc-cccc-cccc-cccccccccccc` |

---

## Step 5 — Create Federated Credentials

This creates the trust link between each Kubernetes Service Account and its Azure Managed Identity.

> [!NOTE]
> **What is a Federated Credential?**
> It tells Azure: "When a pod in AKS cluster X, in namespace Y, using Service Account Z requests a token — trust it as this Managed Identity." No secrets are exchanged — it's all based on OIDC token verification.

### Portal Steps (Repeat for each identity)

1. Go to **Managed Identities** → Click the identity (e.g., `admin-eso-identity`)
2. In the left sidebar → Click **"Federated credentials"**
3. Click **"+ Add credential"**
4. Select scenario: **"Kubernetes accessing Azure resources"**
5. Fill in:

**For admin-eso-identity:**

| Field | Value | Explanation |
|---|---|---|
| **Cluster Issuer URL** | Paste the OIDC Issuer URL from Step 3 | This is the AKS cluster's OIDC endpoint that Azure AD trusts |
| **Namespace** | `your-app-namespace` | The Kubernetes namespace where your admin app runs |
| **Service Account** | `admin-eso-sa` | The K8s service account that admin pods will use |
| **Name** | `admin-federated-cred` | A friendly name for this credential |
| **Audience** | `api://AzureADTokenExchange` | Default value — don't change this |

6. Click **"Add"**

**For frontend-eso-identity:**

| Field | Value |
|---|---|
| **Cluster Issuer URL** | Same OIDC Issuer URL |
| **Namespace** | `your-app-namespace` |
| **Service Account** | `frontend-eso-sa` |
| **Name** | `frontend-federated-cred` |
| **Audience** | `api://AzureADTokenExchange` |

**For backend-eso-identity:**

| Field | Value |
|---|---|
| **Cluster Issuer URL** | Same OIDC Issuer URL |
| **Namespace** | `your-app-namespace` |
| **Service Account** | `backend-eso-sa` |
| **Name** | `backend-federated-cred` |
| **Audience** | `api://AzureADTokenExchange` |

---

## Step 6 — Grant Key Vault Access to Identities

Each Managed Identity needs permission to **read secrets** from its respective Key Vault.

> [!NOTE]
> **What is "Key Vault Secrets User" role?**
> It's an Azure RBAC role that grants **read-only** access to secret values in a Key Vault. The identity can get and list secrets but cannot create, update, or delete them. This follows the principle of **least privilege** — your pods only need to read secrets, never modify them.

### Portal Steps (Repeat for each vault)

**For admin-kv → admin-eso-identity:**

1. Go to **Key vaults** → Click `admin-kv`
2. In the left sidebar → Click **"Access control (IAM)"**
3. Click **"+ Add"** → **"Add role assignment"**

4. **Role tab:**
   - Search for `Key Vault Secrets User`
   - Select it (under "Job function roles")
   - Click **"Next"**

5. **Members tab:**
   - **Assign access to**: Select `Managed identity`
   - Click **"+ Select members"**
   - **Managed identity** dropdown: Select `User-assigned managed identity`
   - Find and select `admin-eso-identity`
   - Click **"Select"**

6. Click **"Review + assign"** → **"Review + assign"** again

**Repeat for:**
- `frontend-kv` → assign `frontend-eso-identity`
- `backend-kv` → assign `backend-eso-identity`

### Verify

For each vault: Go to **Access control (IAM)** → **"Role assignments"** tab → You should see:

| Key Vault | Identity | Role |
|---|---|---|
| `admin-kv` | `admin-eso-identity` | Key Vault Secrets User |
| `frontend-kv` | `frontend-eso-identity` | Key Vault Secrets User |
| `backend-kv` | `backend-eso-identity` | Key Vault Secrets User |

---

## Step 7 — Install External Secrets Operator

> [!NOTE]
> **What is External Secrets Operator (ESO)?**
> It's a Kubernetes operator (a controller that runs inside your cluster) that reads secrets from external providers (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault, etc.) and creates native Kubernetes Secrets. It runs continuously and keeps secrets in sync based on a configurable refresh interval.

This is the only step that requires terminal commands (Helm install on your AKS cluster):

```bash
# Add the ESO Helm chart repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO in its own namespace
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait

# Verify — all 3 pods should be Running
kubectl -n external-secrets get pods
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
external-secrets-xxxxxxxxx-xxxxx                    1/1     Running   0          30s
external-secrets-cert-controller-xxxxxxxxx-xxxxx    1/1     Running   0          30s
external-secrets-webhook-xxxxxxxxx-xxxxx            1/1     Running   0          30s
```

**What each pod does:**
| Pod | Purpose |
|---|---|
| `external-secrets` | Main controller — watches ExternalSecret resources and syncs secrets |
| `external-secrets-cert-controller` | Manages TLS certificates for the webhook |
| `external-secrets-webhook` | Validates ExternalSecret/SecretStore manifests before they're applied |

---

## Step 8 — Create Kubernetes Service Accounts

Create 3 Service Accounts — one per app — each annotated with its Managed Identity's Client ID.

```yaml
# service-accounts.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-eso-sa
  namespace: your-app-namespace                            # ← change to your namespace
  annotations:
    azure.workload.identity/client-id: "<ADMIN_IDENTITY_CLIENT_ID>"    # ← from Step 4
  labels:
    azure.workload.identity/use: "true"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: frontend-eso-sa
  namespace: your-app-namespace                            # ← change to your namespace
  annotations:
    azure.workload.identity/client-id: "<FRONTEND_IDENTITY_CLIENT_ID>" # ← from Step 4
  labels:
    azure.workload.identity/use: "true"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-eso-sa
  namespace: your-app-namespace                            # ← change to your namespace
  annotations:
    azure.workload.identity/client-id: "<BACKEND_IDENTITY_CLIENT_ID>"  # ← from Step 4
  labels:
    azure.workload.identity/use: "true"
```

> [!IMPORTANT]
> **What do these annotations mean?**
> - `azure.workload.identity/client-id` — Tells the AKS Workload Identity webhook which Azure Managed Identity to federate with. When a pod uses this SA, it gets Azure tokens as this identity.
> - `azure.workload.identity/use: "true"` — Enables the webhook to inject the OIDC token volume and environment variables into pods using this SA.

```bash
kubectl apply -f service-accounts.yaml

# Verify
kubectl get sa -n your-app-namespace
```

---

## Step 9 — Create 3 ClusterSecretStores

Each store connects ESO to one Key Vault via one Managed Identity.

```yaml
# cluster-secret-stores.yaml
---
# ─── Admin Key Vault Store ───
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: admin-kv-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      tenantId: "b70fb533-d715-489d-9028-57ffd50ef1a4" # ← your tenant ID
      vaultUrl: "https://admin-kv.vault.azure.net"          # ← your admin KV URL
      serviceAccountRef:
        name: admin-eso-sa
        namespace: your-app-namespace
---
# ─── Frontend Key Vault Store ───
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: frontend-kv-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      tenantId: "b70fb533-d715-489d-9028-57ffd50ef1a4" # ← your tenant ID
      vaultUrl: "https://frontend-kv.vault.azure.net"       # ← your frontend KV URL
      serviceAccountRef:
        name: frontend-eso-sa
        namespace: your-app-namespace
---
# ─── Backend Key Vault Store ───
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: backend-kv-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      tenantId: "b70fb533-d715-489d-9028-57ffd50ef1a4" # ← your tenant ID
      vaultUrl: "https://backend-kv.vault.azure.net"        # ← your backend KV URL
      serviceAccountRef:
        name: backend-eso-sa
        namespace: your-app-namespace
```

> [!NOTE]
> **ClusterSecretStore vs SecretStore:**
> - `ClusterSecretStore` is cluster-wide — any namespace can reference it.
> - `SecretStore` is namespace-scoped — only the namespace it's created in can use it.
> - We use `ClusterSecretStore` for flexibility. If you want strict namespace isolation, change to `SecretStore` and create it in the app's namespace.

```bash
kubectl apply -f cluster-secret-stores.yaml

# Verify — all 3 should show STATUS: Valid, READY: True
kubectl get clustersecretstore
```

Expected:
```
NAME                 AGE   STATUS   CAPABILITIES   READY
admin-kv-store       10s   Valid    ReadOnly       True
frontend-kv-store    10s   Valid    ReadOnly       True
backend-kv-store     10s   Valid    ReadOnly       True
```

---

## Step 10 — Create 3 ExternalSecrets

An `ExternalSecret` tells ESO which secrets to pull from which Key Vault and creates a corresponding Kubernetes Secret in your namespace.

### Option A: Auto-Generate YAML (Recommended)

Since writing dozens of entries manually is tedious, use the provided `generate-external-secret.sh` script to auto-generate the YAML from your `.env` file. It handles hyphen conversion and skips duplicates.

**Usage:**
```bash
# 1. Make the script executable
chmod +x generate-external-secret.sh

# 2. Run for each app (Admin, Frontend, Backend)
./generate-external-secret.sh admin.env    admin    artha admin-kv-store
./generate-external-secret.sh frontend.env frontend artha frontend-kv-store
./generate-external-secret.sh backend.env  backend  artha backend-kv-store

# 3. Apply the generated files
kubectl apply -f external-secret-admin.yaml
kubectl apply -f external-secret-frontend.yaml
kubectl apply -f external-secret-backend.yaml
```

---

### Option B: Manual Way (For Reference)

If you prefer to write the YAML yourself, use these templates:

#### 12.1 Admin ExternalSecret (`external-secret-admin.yaml`)
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: admin-secrets
  namespace: artha
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: admin-kv-store
    kind: ClusterSecretStore
  target:
    name: admin-env-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: DB-HOST
    - secretKey: DB_PORT
      remoteRef:
        key: DB-PORT
```

#### 12.2 Frontend ExternalSecret (`external-secret-frontend.yaml`)
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: frontend-secrets
  namespace: artha
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: frontend-kv-store
    kind: ClusterSecretStore
  target:
    name: frontend-env-secrets
    creationPolicy: Owner
  data:
    - secretKey: API_URL
      remoteRef:
        key: API-URL
```

#### 12.3 Backend ExternalSecret (`external-secret-backend.yaml`)
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: backend-secrets
  namespace: artha
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: backend-kv-store
    kind: ClusterSecretStore
  target:
    name: backend-env-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: DB-HOST
    - secretKey: JWT_SECRET
      remoteRef:
        key: JWT-SECRET

    - secretKey: SMTP_HOST
      remoteRef:
        key: SMTP-HOST

    - secretKey: SMTP_PASSWORD
      remoteRef:
        key: SMTP-PASSWORD

    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: AWS-ACCESS-KEY-ID

    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: AWS-SECRET-ACCESS-KEY

    # ... add ALL your backend secrets
```

```bash
# Apply all 3
kubectl apply -f external-secret-admin.yaml
kubectl apply -f external-secret-frontend.yaml
kubectl apply -f external-secret-backend.yaml

# Verify — all 3 should show STATUS: SecretSynced
kubectl get externalsecret -n your-app-namespace
```

Expected:
```
NAME                AGE   STATUS          READY
admin-secrets       10s   SecretSynced    True
frontend-secrets    10s   SecretSynced    True
backend-secrets     10s   SecretSynced    True
```

---

## Step 11 — Use Secrets in Deployments

### Admin Deployment

```yaml
# deployment-admin.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin
  namespace: your-app-namespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: admin
  template:
    metadata:
      labels:
        app: admin
    spec:
      serviceAccountName: admin-eso-sa          # ← the workload-identity SA
      containers:
        - name: admin
          image: your-registry/admin:latest
          ports:
            - containerPort: 3000
          envFrom:
            - secretRef:
                name: admin-env-secrets         # ← K8s Secret created by ESO
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### Frontend Deployment

```yaml
# deployment-frontend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: your-app-namespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      serviceAccountName: frontend-eso-sa
      containers:
        - name: frontend
          image: your-registry/frontend:latest
          ports:
            - containerPort: 3000
          envFrom:
            - secretRef:
                name: frontend-env-secrets
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### Backend Deployment

```yaml
# deployment-backend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: your-app-namespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      serviceAccountName: backend-eso-sa
      containers:
        - name: backend
          image: your-registry/backend:latest
          ports:
            - containerPort: 3000
          envFrom:
            - secretRef:
                name: backend-env-secrets
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

> [!NOTE]
> **What does `envFrom` do?**
> It takes every key-value pair from the referenced Kubernetes Secret and injects them as environment variables into the container. So if the secret has `DB_HOST=mydb.example.com`, the container will have `DB_HOST` available as `process.env.DB_HOST` (Node.js) or `os.environ['DB_HOST']` (Python).

---

## Step 12 — Verify Environment Variables in Pod

Once your deployments are running, you should verify that the secrets have been correctly injected into the pod as environment variables.

1. **Dump the pod environment variables to a file (sorted)**:
   ```bash
   kubectl exec -n artha deploy/backend -- env | sort > pod-env.txt
   ```

2. **Extract keys from your \`.env\` file for comparison**:
   *(Assuming your original file is named \`backend.env\`)*
   ```bash
   grep '=' backend.env | cut -d'=' -f1 | sort > expected-keys.txt
   ```

3. **Find missing keys (keys in \`.env\` but not in the pod)**:
   ```bash
   comm -23 expected-keys.txt <(cut -d'=' -f1 pod-env.txt | sort)
   ```
   *If this command returns nothing, all your secrets are perfectly synced and injected!*

---

## Step 13 — Remove Secrets from Dockerfile

### Before (❌ Insecure)

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY . .
ENV DB_HOST=mydb.postgres.database.azure.com
ENV DB_PASSWORD=SuperSecret123!
ENV JWT_SECRET=my-jwt-secret
# ... 50 more ENV lines
RUN npm install
CMD ["npm", "start"]
```

### After (✅ Secure)

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
# No ENV lines — all secrets injected at runtime by ESO via K8s Secrets
```

**Why this matters:**
- Docker images are often stored in registries that many people access.
- Anyone who can pull the image can extract the ENV values.
- With ESO, secrets only exist at **runtime** inside the pod's memory — never in the image.

---

## Day-2 Operations: Add / Update / Remove Secrets

### 15.1 ➕ Add a New Secret

**Scenario:** You need to add `STRIPE_API_KEY` to the backend.

**Step 1 — Add to Key Vault (Portal):**
1. Go to **Key vaults** → `backend-kv` → **Secrets** → **"+ Generate/Import"**
2. **Name**: `STRIPE-API-KEY`
3. **Value**: `sk_live_xxxxx`
4. Click **"Create"**

**Step 2 — Add to ExternalSecret YAML:**

Add this entry to `external-secret-backend.yaml` under `spec.data`:
```yaml
    - secretKey: STRIPE_API_KEY
      remoteRef:
        key: STRIPE-API-KEY
```

**Step 3 — Apply & Restart:**
```bash
kubectl apply -f external-secret-backend.yaml

# Force immediate sync
kubectl annotate externalsecret backend-secrets -n your-app-namespace \
  force-sync=$(date +%s) --overwrite

# Restart pods to pick up new env var
kubectl rollout restart deployment/backend -n your-app-namespace
```

**Step 4 — Verify:**
```bash
kubectl get secret backend-env-secrets -n your-app-namespace \
  -o jsonpath='{.data.STRIPE_API_KEY}' | base64 -d
```

---

### 15.2 ✏️ Update an Existing Secret Value

**Scenario:** The `DB_PASSWORD` for backend needs to be rotated.

**Step 1 — Update in Key Vault (Portal):**
1. Go to **Key vaults** → `backend-kv` → **Secrets** → Click `DB-PASSWORD`
2. Click **"+ New Version"**
3. Enter the new value → Click **"Create"**

> [!TIP]
> Key Vault keeps **version history**. The old value is still accessible under previous versions. You can roll back by disabling the new version and enabling the old one.

**Step 2 — Sync & Restart:**
```bash
# No YAML change needed — the mapping is the same, only the value changed.

# Force immediate sync
kubectl annotate externalsecret backend-secrets -n your-app-namespace \
  force-sync=$(date +%s) --overwrite

# Restart pods
kubectl rollout restart deployment/backend -n your-app-namespace
```

> [!NOTE]
> If you don't force-sync, ESO will automatically pick up the new value at the next `refreshInterval` (default: 1 hour). The force-sync is only needed if you want it **immediately**.

---

### 15.3 ❌ Remove a Secret

**Scenario:** `LEGACY_API_KEY` is no longer needed in the admin app.

**Step 1 — Remove from ExternalSecret YAML:**

Delete this block from `external-secret-admin.yaml`:
```yaml
    # DELETE this entry:
    - secretKey: LEGACY_API_KEY
      remoteRef:
        key: LEGACY-API-KEY
```

**Step 2 — Apply & Restart:**
```bash
kubectl apply -f external-secret-admin.yaml
kubectl annotate externalsecret admin-secrets -n your-app-namespace \
  force-sync=$(date +%s) --overwrite
kubectl rollout restart deployment/admin -n your-app-namespace
```

**Step 3 — Delete from Key Vault (Portal):**
1. Go to **Key vaults** → `admin-kv` → **Secrets** → Click `LEGACY-API-KEY`
2. Click **"Delete"** → Confirm

> [!NOTE]
> With **soft-delete** enabled (on by default), deleted secrets go to a "Deleted secrets" state for 90 days. You can recover them from: Key vaults → Secrets → **"Manage deleted secrets"** (top bar). To permanently delete, click **"Purge"** from the deleted secrets view.

---

### 15.4 📋 Day-2 Quick Reference

| Action | Key Vault (Portal) | ExternalSecret YAML | Pod Restart? |
|---|---|---|---|
| **Add new secret** | Create new secret | Add new `data` entry | ✅ Yes |
| **Update value** | Create new version | ❌ No change needed | ✅ Yes |
| **Remove secret** | Delete (optional) | Remove `data` entry | ✅ Yes |
| **Rename env var** | No change | Update `secretKey` | ✅ Yes |

---

### 15.5 Auto-Restart Pods on Secret Change (Optional)

By default, pods **do not auto-restart** when secrets change — you must manually run `kubectl rollout restart`. To automate this:

**Install Stakater Reloader:**
```bash
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update
helm install reloader stakater/reloader \
  --namespace reloader \
  --create-namespace
```

**Add this annotation to each Deployment:**
```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

**Now the flow is fully automatic:**
1. You update a secret value in Key Vault (Portal)
2. ESO syncs the new value → K8s Secret updates
3. Reloader detects the Secret change → automatically restarts the pods
4. **Zero manual intervention** for value updates

---

---

## Verification & Troubleshooting

### Full Verification Checklist

```bash
# 1. Check all ClusterSecretStores are healthy
kubectl get clustersecretstore
# All should show STATUS: Valid, READY: True

# 2. Check all ExternalSecrets are synced
kubectl get externalsecret -n your-app-namespace
# All should show STATUS: SecretSynced, READY: True

# 3. Check K8s Secrets were created
kubectl get secrets -n your-app-namespace | grep env-secrets
# Should see: admin-env-secrets, frontend-env-secrets, backend-env-secrets

# 4. Verify a specific secret value
kubectl get secret backend-env-secrets -n your-app-namespace \
  -o jsonpath='{.data.DB_HOST}' | base64 -d

# 5. Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# 6. Describe an ExternalSecret for detailed events
kubectl describe externalsecret backend-secrets -n your-app-namespace

# 7. Check pod env vars
kubectl exec -n your-app-namespace deploy/backend -- env | grep DB_HOST
```

### Common Issues

| Issue | Cause | Fix |
|---|---|---|
| ClusterSecretStore shows `Invalid` | Workload Identity not configured properly | Verify: OIDC enabled on AKS, federated credential exists, SA has correct annotation and label |
| `403 Forbidden` | Missing RBAC on Key Vault | Portal: Key vault → IAM → verify roles (see section below) |
| `SecretNotFound` in ESO logs | Secret name mismatch | Check hyphens vs underscores. `remoteRef.key` must exactly match the Key Vault secret name (hyphens) |
| Pod env vars empty | Wrong `secretRef.name` | Ensure `envFrom.secretRef.name` in Deployment matches `target.name` in ExternalSecret |
| Secrets not updating | `refreshInterval` too long | Lower to `5m` or use `force-sync` annotation |

---

## Troubleshooting: RBAC and Permissions

If you get a **403 Forbidden** or **✗ FAILED / ERROR** when running the script or during ESO sync, it is almost certainly an RBAC permission issue.

### A. Who needs which role?

Azure Key Vault uses two different types of permissions. You must assign the correct one to the correct identity:

1. **YOU (The User running the script)**:
    - **Role**: `Key Vault Secrets Officer`
    - **Why**: This role allows you to **Create** and **Update** secrets.
    - **Where**: Assign this to your user account (or the service principal you're logged in with) on the Key Vault's Access Control (IAM) page.

2. **THE OPERATOR (The Managed Identity used by ESO)**:
    - **Role**: `Key Vault Secrets User`
    - **Why**: This role only allows **Reading** secret values. The operator doesn't need to create them.
    - **Where**: Assign this to your Managed Identity (e.g., `backend-eso-identity`) on the Key Vault's Access Control (IAM) page.

### B. How to Assign Roles (Portal)

1. Go to **Key vaults** → Click your vault (e.g., `backend-kv`)
2. Click **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**
4. Search for the role (**Secrets Officer** for you, **Secrets User** for the Managed Identity)
5. Select the role and click **Next**
6. Select **User, group, or service principal** (for you) or **Managed identity** (for ESO identity)
7. Select the member and click **Review + assign**

> [!IMPORTANT]
> Role assignments can take **up to 5-10 minutes** to propagate in Azure. If it fails immediately after you assign the role, wait a few minutes and try again.

---

## Security Best Practices


### Enable Soft-Delete & Purge Protection (Portal)

1. Go to **Key vaults** → Click your vault → **Properties** (left sidebar)
2. **Soft-delete**: Should be `Enabled` (on by default for new vaults)
3. **Purge protection**: Toggle to `Enabled`
4. Click **"Save"**

> [!IMPORTANT]
> **Purge protection** prevents anyone from permanently deleting secrets before the retention period (90 days). Once enabled, it **cannot be disabled**. This protects against accidental or malicious deletion.

### Enable Diagnostic Logging (Portal)

1. Go to **Key vaults** → Click your vault → **Diagnostic settings** (left sidebar under Monitoring)
2. Click **"+ Add diagnostic setting"**
3. **Setting name**: `kv-audit-logs`
4. Check **"audit"** under Logs
5. **Destination**: Select `Send to Log Analytics workspace` → Choose your workspace
6. Click **"Save"**

This logs all access to your Key Vault — who read which secret and when.

### Restrict Network Access (Portal)

1. Go to **Key vaults** → Click your vault → **Networking** (left sidebar)
2. Change to **"Allow access from Selected networks"**
3. Under **Virtual networks** → Click **"+ Add a virtual network"** → Select your AKS VNET and subnet
4. Click **"Apply"** → **"Save"**

This ensures only your AKS cluster can reach the Key Vault.

### Additional Recommendations

- **Never commit `.env` files to Git** — add `.env`, `*.env` to `.gitignore`
- **Use separate Key Vaults per environment** (dev, staging, prod)
- **Set secret expiration dates** for credentials that must be rotated periodically
- **Review access logs monthly** via Log Analytics or Key Vault → Logs

---




---

## Quick Reference — All Resources Created

### Azure Resources (Portal)

| Resource | Name | Type |
|---|---|---|
| Key Vault | `admin-kv` | Secret store for admin app |
| Key Vault | `frontend-kv` | Secret store for frontend app |
| Key Vault | `backend-kv` | Secret store for backend app |
| Managed Identity | `admin-eso-identity` | Identity for admin ESO access |
| Managed Identity | `frontend-eso-identity` | Identity for frontend ESO access |
| Managed Identity | `backend-eso-identity` | Identity for backend ESO access |
| Federated Credential | `admin-federated-cred` | Links K8s SA → admin identity |
| Federated Credential | `frontend-federated-cred` | Links K8s SA → frontend identity |
| Federated Credential | `backend-federated-cred` | Links K8s SA → backend identity |
| RBAC assignment | Key Vault Secrets User × 3 | Read access per vault |

### Kubernetes Resources

| Resource | Name | Purpose |
|---|---|---|
| ServiceAccount × 3 | `admin-eso-sa`, `frontend-eso-sa`, `backend-eso-sa` | Workload Identity SAs |
| ClusterSecretStore × 3 | `admin-kv-store`, `frontend-kv-store`, `backend-kv-store` | Connects ESO ↔ Key Vaults |
| ExternalSecret × 3 | `admin-secrets`, `frontend-secrets`, `backend-secrets` | Defines what to sync |
| Secret × 3 (auto-created) | `admin-env-secrets`, `frontend-env-secrets`, `backend-env-secrets` | K8s Secrets with env vars |

### Files to Create

| File | Purpose |
|---|---|
| `service-accounts.yaml` | 3 K8s SAs with Workload Identity annotations |
| `cluster-secret-stores.yaml` | 3 ClusterSecretStores connecting ESO ↔ Key Vaults |
| `external-secret-admin.yaml` | Maps admin Key Vault secrets to K8s Secret |
| `external-secret-frontend.yaml` | Maps frontend Key Vault secrets to K8s Secret |
| `external-secret-backend.yaml` | Maps backend Key Vault secrets to K8s Secret |
| `deployment-admin.yaml` | Admin deployment with `envFrom` |
| `deployment-frontend.yaml` | Frontend deployment with `envFrom` |
| `deployment-backend.yaml` | Backend deployment with `envFrom` |
| `generate-external-secret.sh` | Auto-generate ExternalSecret YAML from `.env` |

---

> **Done!** All secrets for Admin, Frontend, and Backend are now managed in 3 separate Azure Key Vaults, synced to Kubernetes by ESO, and injected into pods at runtime — with zero secrets in your Dockerfiles. 🎉
