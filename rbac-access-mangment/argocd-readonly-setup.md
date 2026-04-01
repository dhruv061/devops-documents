# Argo CD Readonly User Configuration (sagar-chhatrala)

This guide provides a clean, step-by-step process to add a local user `sagar-chhatrala` with read-only access to Argo CD.

---

## 1. Prerequisites: Install Argo CD CLI
If not already installed on Ubuntu:
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

---

## 2. Enable Local Account
Update the `argocd-cm` ConfigMap to allow the new user to log in.

1. **Edit ConfigMap**: `kubectl edit cm argocd-cm -n argocd`
2. **Add Data**:
   ```yaml
   data:
     accounts.sagar-chhatrala: login
   ```

---

## 3. Assign Readonly Role
Update the `argocd-rbac-cm` ConfigMap. Use the strict format **without spaces** after commas.

1. **Edit ConfigMap**: `kubectl edit cm argocd-rbac-cm -n argocd`
2. **Apply Policy**:
   ```yaml
   data:
     policy.csv: |
       g,sagar-chhatrala,role:readonly
     policy.default: role:readonly
   ```

---

## 4. Set User Password (IMPORTANT)
The new account `sagar-chhatrala` has no password by default. You **must** log in as an administrator to set it.

### Via CLI
```bash
# 1. Log in as admin
argocd login <ARGOCD_SERVER> --grpc-web --username admin --password <your-admin-password>

# 2. Set the password for the new user
argocd account update-password --account sagar-chhatrala --new-password <your-secret-password>
```

### Via UI
1. Log in to the portal as **admin**.
2. Go to **Settings** -> **User Management**.
3. Click `sagar-chhatrala` -> **UPDATE PASSWORD**.

---

## 5. Verification
Log out of admin and log in as the new user:

```bash
# 1. Log out
argocd logout <ARGOCD_SERVER> --grpc-web

# 2. Log in as new user
argocd login <ARGOCD_SERVER> --grpc-web --username sagar-chhatrala --password <your-secret-password>

# 3. Check permission (Should say 'no' for sync/delete)
argocd account can-i sync applications '*' --grpc-web
argocd account can-i delete applications '*' --grpc-web
```

---

## How to Remove the User
1. **Remove from RBAC**: `kubectl edit cm argocd-rbac-cm -n argocd` -> Delete the `g,sagar-chhatrala...` line.
2. **Remove Account**: `kubectl edit cm argocd-cm -n argocd` -> Delete the `accounts.sagar-chhatrala: login` line.

---

## Command Summary Table

| Category | Command | Description |
| :--- | :--- | :--- |
| **Auth** | `argocd login <SERVER> --grpc-web` | Log in to CLI |
| **Auth** | `argocd account update-password --account <USER>` | Set user password |
| **Debug** | `argocd account get-user-info --grpc-web` | Check current session |
| **Ops** | `kubectl rollout restart deployment argocd-server -n argocd` | Apply changes |
