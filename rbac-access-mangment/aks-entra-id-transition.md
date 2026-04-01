# Transitioning AKS to Azure Entra ID (Azure AD)

This guide explains how to move your AKS cluster from "Local accounts" to "Microsoft Entra ID authentication" and the impact this has on your current setup.

---

## 1. The Transition Process
To enable Entra ID authentication on your existing cluster:

1.  **Open Azure Portal**: Go to your **AKS Cluster** -> **Configuration**.
2.  **Security Configuration**: In the settings menu, select **Security configuration**.
3.  **Update Authentication**:
    - Change **Authentication and Authorization** to: `Microsoft Entra ID authentication with Azure RBAC`.
4.  **Admin Group**: You will be asked to select a **Microsoft Entra ID group** to have cluster admin rights. Choose your DevOps or Admin group.
5.  **Apply**: Click **Apply** at the bottom. The cluster will update (this takes ~5-10 minutes).

---

## 2. Impact Analysis: What happens next?

### ⚠️ Will it break my existing workloads?
**No.** Transitioning to Entra ID is a control-plane update. Your running applications, pods, and services will **not be restarted** or affected.

### ⚠️ What happens to the local `sagar-chhatrala` account?
**It stays active.** Local ServiceAccounts and their secrets (tokens) are **not deleted**.
- Your existing `readonly-config.yaml` will **still work** exactly as before. 
- You do NOT need to recreate local accounts unless you want to move them to Entra ID for better security.

### ⚠️ What changes for the users?
- New users who use Entra ID will run `az aks get-credentials` and then be prompted to log in via their browser.
- They will no longer need a static token file; they will use their own Azure email address.

---

## 3. Assigning New Read-Only Access (via Entra ID)
Once the transition is complete, you can grant read-only access to any Azure user:

1.  **IAM Settings**: Go to **Access Control (IAM)** on the cluster.
2.  **Add Assignment**: Click **+ Add** -> **Add role assignment**.
3.  **IMPORTANT**: You must add **TWO** separate roles to the user:
    *   **Role 1: `Azure Kubernetes Service RBAC Reader`** (To see resources inside the cluster).
    *   **Role 2: `Azure Kubernetes Service Cluster User Role`** (To be allowed to run `az aks get-credentials`).
4.  **Assignee**: Select the user's email.
5.  **Save**: Click **Review + assign**.

---

## 4. How the User Connects
The person with the new access runs these commands on their local machine:

1. **Install Azure CLI, kubectl, and kubelogin**:
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Install kubectl and kubelogin
   sudo az aks install-cli
   ```
   *Note: If `az aks install-cli` doesn't install `kubelogin` on your system, you can install it manually from [GitHub](https://github.com/Azure/kubelogin/releases).*

2. **Login to Azure**:
   ```bash
   az login
   ```
3. **Get Cluster Credentials**:
   ```bash
   az aks get-credentials --resource-group <RG> --name <CLUSTER>
   ```
4. **Verify Access**:
   ```bash
   kubectl get pods -A
   ```
   *(You will be asked to log in via a browser/device code the first time you run this)*

---

## Technical Detail: Why is `kubelogin` required?

You might notice that the previous **Local RBAC** method did not require `kubelogin`. Here is the difference:

| Feature | Local RBAC (Static Token) | Azure Entra ID (Dynamic) |
| :--- | :--- | :--- |
| **Authentication** | Static string in `kubeconfig` | Your Azure AD Login (Email/MFA) |
| **Tooling** | Just `kubectl` | `kubectl` + `kubelogin` plugin |
| **Security** | **Lower** (Token never expires) | **Higher** (Short-lived access) |
| **MFA Support** | No | **Yes** (Inherits Azure AD policies) |

**The Role of `kubelogin`**:
Native `kubectl` does not know how to "log in" to a browser or handle Azure AD identity tokens. The **`kubelogin`** plugin act as the "middle-man" that handles the secure authentication process and provides a temporary token to `kubectl`.

---

## Summary of Benefits
*   **MFA Support**: Users log in with their Azure credentials (supporting 2FA).
*   **Centralized Offboarding**: Disabling a user in Azure Active Directory automatically removes their access to the cluster.
*   **No Permanent Secrets**: No more long-lived `kubeconfig` files floating around.
