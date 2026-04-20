# Guide: Setting up SMTP on Azure with a Custom Domain

This guide provides step-by-step instructions for configuring SMTP services using **Azure Communication Services (ACS)** and **Email Communication Services (ECS)** via the Azure Portal.

---

## Phase 1: Provisioning Resources

You need two primary resources: **Azure Communication Services (ACS)** (the logic/messaging engine) and **Email Communication Services (ECS)** (the email-specific delivery engine).

### 1. Create Email Communication Services (ECS)
1.  Search for **Email Communication Services** in the Azure Portal.
2.  Click **Create**.
3.  Select your **Subscription** and **Resource Group**.
4.  **Data Location**: Choose a region (e.g., United States).
5.  Click **Review + Create**, then **Create**.

### 2. Create Azure Communication Services (ACS)
1.  Search for **Communication Services** in the Azure Portal.
2.  Click **Create**.
3.  Fill in the Subscription, Resource Group, and a unique **Resource Name**.
4.  **Data Location**: Set to "United States" or your preferred region.
5.  Click **Review + Create**, then **Create**.

---

## Phase 2: Domain Configuration & Verification

Azure requires proof of ownership and security configuration (SPF/DKIM) for custom domains.

1.  Navigate to your **Email Communication Services** resource.
2.  In the left sidebar, under **Settings**, select **Provision domains**.
3.  Click **Add domain** -> **Custom domain**.
4.  Enter your domain name (e.g., `example.com`) and click **Confirm**.
5.  The domain will appear in the list as `In progress`. Click on it to see the **DNS records**.

### Required DNS Records
You must add the following records to your DNS provider (e.g., GoDaddy, Cloudflare, Azure DNS):

| Record Type | Name / Host | Value | Purpose |
| :--- | :--- | :--- | :--- |
| **TXT** | @ | `ms-domain-verification=...` | Ownership Verification |
| **TXT** | @ | `v=spf1 include:spf.protection.outlook.com -all`* | SPF (Spam Protection) |
| **CNAME** | <dkim1_selector> | <dkim1_value> | DKIM Selector 1 |
| **CNAME** | <dkim2_selector> | <dkim2_value> | DKIM Selector 2 |

> [!TIP]
> *Note: Copy the specific SPF and DKIM values directly from the Azure Portal as they contain unique identifiers.*

6.  After adding the records, click **Verify** in the Azure Portal. It may take 15-30 minutes for DNS propagation.

---

## Phase 3: Connecting Email to Communication Services

Now you must link the verified domain to your main ACS resource.

1.  Navigate to your **Azure Communication Services** resource.
2.  Under **Email** in the left sidebar, select **Domains**.
3.  Click **Connect domain**.
4.  Select the **Subscription** and **Resource Group** where your **Email Communication Service** is located.
5.  Choose the verified **Custom Domain**.
6.  Click **Connect**.

---

## Phase 4: SMTP Authentication Setup

Azure SMTP requires authentication via a **Microsoft Entra ID (Azure AD)** App Registration.

### 1. Create App Registration
1.  Navigate to **Microsoft Entra ID** (formerly Azure AD) in the portal.
2.  Go to **App registrations** -> **New registration**.
3.  Name it (e.g., `Azure-SMTP-Bot`) and click **Register**.
4.  Copy the **Application (client) ID** and **Directory (tenant) ID**. You will need these later.
5.  Go to **Certificates & secrets** -> **New client secret**.
6.  Set an expiration and click **Add**. **COPY THE VALUE IMMEDIATELY** (this is your SMTP password).

### 2. Create Custom SMTP Role (Least Privilege)
To ensure security, create a role that **only** allows sending emails:
1.  Navigate to your **Resource Group** in the Azure Portal.
2.  Select **Access control (IAM)** -> **Add** -> **Add custom role**.
3.  Name it: `Azure SMTP Sender`.
4.  In the **Permissions** tab, click **Add permissions** and search for/add these three specific actions:
    *   `Microsoft.Communication/EmailServices/write`
    *   `Microsoft.Communication/CommunicationServices/Read`
5.  Click **Review + create**.

### 3. Assign Custom Role
1.  Navigate to your **Azure Communication Services** resource (`knovator-smtp`).
2.  Select **Access Control (IAM)** -> **Add** -> **Add role assignment**.
3.  Search for the role you just created: `Azure SMTP Sender`.
4.  Assign access to: **User, group, or service principal**.
5.  Click **Select members** and search for your **App Registration** (e.g., `Azure-SMTP-Bot`).
6.  Click **Review + assign**.

---

## Phase 5: SMTP Connection Details

Use these settings in your application or SMTP client:

| Setting | Value |
| :--- | :--- |
| **SMTP Server** | `smtp.azurecomm.net` |
| **Port** | `587` |
| **Encryption** | `STARTTLS` (Enabled) |
| **Username** | `<ACS_Resource_Name>.<App_Registration_Client_ID>.<Tenant_ID>` |
| **Password** | The **Client Secret Value** (from Phase 4) |

> [!IMPORTANT]
> **Username Formatting**: Use dots (`.`) or pipes (`|`) as separators.
> Example: `MyACSRes.12345678-abcd-1234.98765432-1234-abcd`

### From Address
The **From** address must match the `MailFrom` address configured in your Email Communication Service domain settings.
1.  Go to **Email Communication Services** -> **Provision domains** -> **[Your Domain]** -> **MailFrom addresses**.
2.  The default is usually `donotreply@yourdomain.com`, but you can add others like `info@yourdomain.com`.
