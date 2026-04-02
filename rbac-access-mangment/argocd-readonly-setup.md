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
Update the `argocd-cm` ConfigMap to allow the new users to log in.

1. **Edit ConfigMap**: `kubectl edit cm argocd-cm -n argocd`
2. **Add Data**:
   ```yaml
   data:
     accounts.sagar-chhatrala: login
     accounts.dev-user1: login
     accounts.dev-user2: login
   ```

---

## 3. RBAC for Readonly User
Update the `argocd-rbac-cm` ConfigMap for readonly access.

1. **Edit ConfigMap**: `kubectl edit cm argocd-rbac-cm -n argocd`
2. **Apply Policy**:
   ```yaml
   data:
     policy.csv: |
       g,sagar-chhatrala,role:readonly
     policy.default: ""
   ```

> [!IMPORTANT]
> Setting `policy.default: ""` is **required** to ensure users only see the applications they are explicitly granted access to. If set to `role:readonly`, all users will see all applications.

---

## 4. RBAC for Developer
This role allows users to **Sync**, **Refresh**, and **View** specific applications.

1. **Edit ConfigMap**: `kubectl edit cm argocd-rbac-cm -n argocd`
2. **Define Role & Group Mapping**:
   ```yaml
   data:
     policy.csv: |
       # Readonly User (Full View Access)
       g,sagar-chhatrala,role:readonly
       
       # Developer Role (View + Sync ONLY for specific application)
       p,role:developer,applications,get,my-project/my-app,allow
       p,role:developer,applications,sync,my-project/my-app,allow
       
       # Mapping Multiple Users to Developer Group
       g,dev-user1,role:developer
       g,dev-user2,role:developer
     policy.default: ""
   ```

> [!NOTE]
> Replace `my-project/my-app` with your actual project and application name. Use `*/*` for all applications.

---

## 5. Set User Passwords (IMPORTANT)
The new accounts have no passwords by default. You **must** log in as an administrator to set them.

### Via CLI
```bash
# 1. Log in as admin
argocd login <ARGOCD_SERVER> --grpc-web --username admin --password <your-admin-password>

# 2. Set the password for each user
argocd account update-password --account sagar-chhatrala --new-password <password>
argocd account update-password --account dev-user1 --new-password <password>
argocd account update-password --account dev-user2 --new-password <password>
```

### Via UI
1. Log in to the portal as **admin**.
2. Go to **Settings** -> **User Management**.
3. Click on the specific user (e.g., `dev-user1`) -> **UPDATE PASSWORD**.

---

## 6. Verification
Log out of admin and log in as a developer user:

```bash
# 1. Log out
argocd logout <ARGOCD_SERVER> --grpc-web

# 2. Log in as developer user
argocd login <ARGOCD_SERVER> --grpc-web --username dev-user1 --password <password>

# 3. Check permission (Should say 'yes' for sync, 'no' for delete)
argocd account can-i get applications 'my-project/my-app' --grpc-web
argocd account can-i sync applications 'my-project/my-app' --grpc-web
argocd account can-i delete applications '*' --grpc-web
```
---

## 7. User Permission Matrix (Quick Check)
If you want to see all applications you have access to and check your specific permissions in one go:

### View Accessible Applications
```bash
argocd app list
```

### Check All Actions for an App (One-Liner)
Run this command after logging in to see a "Yes/No" matrix for a specific application:
```bash
APP="my-project/my-app"; for action in get sync delete; do echo -n "$action: "; argocd account can-i $action applications "$APP" --grpc-web; done
```
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
