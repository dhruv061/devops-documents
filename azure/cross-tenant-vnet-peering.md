# Cross-Tenant VNet Peering — Complete Setup Guide (Portal)

> Peer two Azure VNets in **different Azure Accounts** (different Tenants & Subscriptions) using the **Azure Portal** by creating a shared Azure AD user.

---

## Overview

When two Azure accounts use **separate Microsoft Account logins** (e.g., personal emails), the Portal's "Switch directory" feature won't show both tenants. The fix is to create a **native Azure AD user** in one tenant and invite it as a guest in the other — this enables proper cross-tenant visibility.

```
Account A (Tenant A)                    Account B (Tenant B)
┌────────────────────┐                  ┌────────────────────┐
│  VNet A             │                  │  VNet B             │
│  10.224.0.0/12      │   ◄── PEER ──►  │  10.0.0.0/16        │
│                     │                  │                     │
│  peering-admin      │                  │  peering-admin      │
│  (Guest User)       │                  │  (Native AD User)   │
└────────────────────┘                  └────────────────────┘
```

---

## Terminology

| Term | Example |
|---|---|
| **Account A** | `accountarthajobboard.onmicrosoft.com` (Tenant ID: `b70fb533-...`) |
| **Account B** | `bhavikvchavdagmail.onmicrosoft.com` (Tenant ID: `f4cbdcd7-...`) |
| **peering-admin** | A new Azure AD user created in Account B for cross-tenant access |

---

## Prerequisites

- Admin/Owner access to both Azure accounts.
- VNets must have **non-overlapping IP address ranges** (see [Troubleshooting](#troubleshooting)).

---

## Step 1: Create a Native Azure AD User in Account B

1. Log in to **Azure Portal** with **Account B** admin credentials.
2. Go to **Microsoft Entra ID** → **Users** → **New user** → **Create new user**.
3. Fill in:
   - **User principal name:** `peering-admin`
   - **Display name:** `peering-admin`
   - **Password:** Set a strong password (note it down)
4. Click **Create**.

**Result:** User `peering-admin@bhavikvchavdagmail.onmicrosoft.com` is created.

---

## Step 2: Assign Network Contributor to peering-admin on VNet B

1. Still in **Account B** Portal.
2. Go to **Virtual Network B** → **Access control (IAM)**.
3. Click **+ Add** → **Add role assignment**.
4. **Role:** Network Contributor → **Next**.
5. **Members:** Select `peering-admin` → **Review + Assign**.

---

## Step 3: Invite peering-admin as Guest in Account A

1. Log in to **Azure Portal** with **Account A** admin credentials.
2. Go to **Microsoft Entra ID** → **Users** → **New user** → **Invite external user**.
3. **Email:** `peering-admin@bhavikvchavdagmail.onmicrosoft.com`
4. Click **Invite**.

**Result:** The user appears in Account A's user list with B2B Invitation status: **"Pending acceptance"**.

---

## Step 4: Accept the Guest Invitation

Since `peering-admin` is an Azure AD user (no personal email inbox), accept the invitation using the **direct login method**:

1. Open an **Incognito / Private browser window**.
2. Navigate to this URL (replace with **Account A's Tenant ID**):
   ```
   https://portal.azure.com/<Account-A-Tenant-ID>
   ```
   Example:
   ```
   https://portal.azure.com/b70fb533-d715-489d-9028-57ffd50ef1a4
   ```
3. Log in with:
   - **Username:** `peering-admin@bhavikvchavdagmail.onmicrosoft.com`
   - **Password:** The password you set in Step 1.
4. First-time login will ask to **change the password** → Set a new password.
5. A **consent/permissions prompt** will appear → Click **Accept**.
6. You should now see Account A's Portal → Invitation is accepted ✅

### Verify Acceptance

Go back to **Account A** Portal (as your admin user) → **Microsoft Entra ID** → **Users** → Find `peering-admin`:
- B2B Invitation status should be: **"Accepted"** (not "Pending acceptance").

---

## Step 5: Assign Network Contributor to peering-admin on VNet A

1. In **Account A** Portal (as admin).
2. Go to **Virtual Network A** → **Access control (IAM)**.
3. Click **+ Add** → **Add role assignment**.
4. **Role:** Network Contributor → **Next**.
5. **Members:** Search for `peering-admin` (the guest user) → Select → **Review + Assign**.

---

## Step 6: Verify Cross-Tenant Directory Access

1. Open **Incognito browser** → Go to [portal.azure.com](https://portal.azure.com).
2. Log in as `peering-admin@bhavikvchavdagmail.onmicrosoft.com`.
3. Click your **profile icon** (top-right) → **"Directories + subscriptions"**.
4. You should see **BOTH** directories:
   - `accountarthajobboard.onmicrosoft.com` (Account A — as Guest)
   - `bhavikvchavdagmail.onmicrosoft.com` (Account B — Home)
5. If both appear → Proceed to create peering ✅

---

## Step 7: Create Peering — VNet A → VNet B

1. Log in to Portal as `peering-admin@bhavikvchavdagmail.onmicrosoft.com`.
2. **Switch directory** to **Account A** (where VNet A lives).
3. Navigate to **Virtual Network A** → **Peerings** → **+ Add**.
4. Fill in:

| Field | Value |
|---|---|
| **Peering link name** | `LinkTo-VNetB` |
| **I know my resource ID** | ✅ Check |
| **Resource ID** | Paste **VNet B's Resource ID** |
| **Directory** | Select **Account B's directory** from dropdown |

5. Click **Authenticate** → Log in as `peering-admin` → Authentication successful ✅
6. Configure traffic settings:

| Setting | Value |
|---|---|
| Allow VNet access | ✅ |
| Allow forwarded traffic | ✅ (if needed) |
| Allow gateway transit | As needed |

7. Click **Add**.

> [!IMPORTANT]
> After Step 7, VNet A's peering will show:
> - **Peering state:** `Initiated`
> - **Peering sync status:** `Remote sync required`
>
> This is **normal**. Do **NOT** click the "Sync" button — it will fail with a "wrong issuer" error.
> Instead, proceed to **Step 8** to create the reverse peering. The status will automatically change to **"Connected"** once both sides have a peering entry.

---

## Step 8: Create Peering — VNet B → VNet A

1. Still logged in as `peering-admin`.
2. **Switch directory** to **Account B** (where VNet B lives).
3. Navigate to **Virtual Network B** → **Peerings** → **+ Add**.
4. Fill in:

| Field | Value |
|---|---|
| **Peering link name** | `LinkTo-VNetA` |
| **I know my resource ID** | ✅ Check |
| **Resource ID** | Paste **VNet A's Resource ID** |
| **Directory** | Select **Account A's directory** from dropdown |

5. Click **Authenticate** → Log in as `peering-admin`.
6. Configure traffic settings (same as Step 7).
7. Click **Add**.

---

## Step 9: Verify Peering

1. Go to **VNet A** → **Peerings** → Status: **"Connected"** ✅
2. Go to **VNet B** → **Peerings** → Status: **"Connected"** ✅

> Both sides must show "Connected". If one shows "Initiated", the other side's peering hasn't been created yet.

---

## Troubleshooting

### ❌ Overlapping Address Space (Transitive Conflict)

**Error:** `address space overlaps with address space of virtual network vnet-XXXXX already peered`

This does NOT mean your two VNets directly overlap. It means:

```
VNet A (10.224.0.0/12)    ❌ CONFLICTS with existing peer
         ↑
VNet B ── already peered with ──► vnet-XXXXX (10.224.0.0/12)
```

**Azure Rule:** If VNet B is already peered with a VNet using `10.224.0.0/12`, it **cannot** also peer with another VNet using the same range.

**Fix:**
- Check VNet B → **Peerings** → identify the existing peering.
- If the old peering is no longer needed → **Delete it** → Retry.
- If both peerings are needed → Change one VNet's address space to a non-overlapping range.

### ❌ Directory Dropdown Shows `undefined` or Wrong ID

**Cause:** The guest invitation was not accepted.

**Fix:** Follow [Step 4](#step-4-accept-the-guest-invitation) — use the direct URL method.

### ❌ "Access token is from the wrong issuer"

**Cause:** Wrong directory selected OR authentication failed.

**Fix:** Ensure you selected the **remote** directory (not your own) in the dropdown, then click Authenticate.

### ❌ Authenticate Button is Greyed Out

**Cause:** No directory is selected.

**Fix:** Select the remote tenant from the Directory dropdown first.

### ❌ "Remote sync required" / "Initiated" After Creating Peering

**Cause:** Only one side of the peering exists. Azure VNet peering requires **both** sides.

**Fix:** Create the reverse peering from VNet B → VNet A (Step 8). Do NOT use the "Sync" button — it will show a "wrong issuer" error because the Directory defaults to your own tenant. The status automatically becomes "Connected" once the reverse peering is created.

---

## CLI Fallback

If the Portal still doesn't work, use Azure CLI:

```bash
# Login to Account A
az login --tenant <Tenant-A-ID> --use-device-code
az account set --subscription <Sub-A-ID>

# Create peering A → B
az network vnet peering create \
  --name LinkToVNetB \
  --resource-group <RG-A> \
  --vnet-name <VNet-A> \
  --remote-vnet "<VNet-B-Resource-ID>" \
  --allow-vnet-access

# Login to Account B
az login --tenant <Tenant-B-ID> --use-device-code
az account set --subscription <Sub-B-ID>

# Create peering B → A
az network vnet peering create \
  --name LinkToVNetA \
  --resource-group <RG-B> \
  --vnet-name <VNet-B> \
  --remote-vnet "<VNet-A-Resource-ID>" \
  --allow-vnet-access
```

---

## Summary Flow

```
Step 1: Create peering-admin user in Account B
         ↓
Step 2: Assign Network Contributor on VNet B
         ↓
Step 3: Invite peering-admin as Guest in Account A
         ↓
Step 4: Accept invitation via direct URL login
         ↓
Step 5: Assign Network Contributor on VNet A
         ↓
Step 6: Verify both directories visible in "Switch directory"
         ↓
Step 7: Create Peering VNet A → VNet B (select remote directory + authenticate)
         ↓
Step 8: Create Peering VNet B → VNet A (select remote directory + authenticate)
         ↓
Step 9: Verify both show "Connected" ✅
```
