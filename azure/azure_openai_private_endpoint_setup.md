# Secure Azure OpenAI Access via Private Endpoint for Azure Container Apps

This guide walkthrough the steps to configure a **Private Endpoint** for your Azure OpenAI service. This ensures that your Azure Container App (ACA) communicates with the AI model over a private IP address within your Virtual Network (VNet), completely bypassing the public internet.

---

## 📋 Prerequisites

Before starting, ensure you have:
1. An existing **Azure Virtual Network (VNet)**.
2. A **Subnet** within that VNet designated for Private Endpoints (e.g., `snet-pe`).
3. An **Azure OpenAI** resource.
4. An **Azure Container App Environment** integrated with the same VNet (or a peered VNet).

---

## 🚀 Step 1: Create the Private Endpoint

1. **Navigate to Azure OpenAI**:
   - In the [Azure Portal](https://portal.azure.com), search for **Azure OpenAI** and select your resource.
2. **Open Networking Settings**:
   - Under the **Resource Management** section in the left sidebar, click on **Networking**.
3. **Add Private Endpoint**:
   - Click the **Private endpoint connections** tab.
   - Click **+ Private endpoint**.
4. **Basics Tab**:
   - **Subscription/Resource Group**: Select your existing RG.
   - **Name**: e.g., `pe-openai-prod`.
   - **Region**: Must be the same region as your VNet.
5. **Resource Tab**:
   - **Connection method**: Connect to an Azure resource in my directory.
   - **Resource type**: `Microsoft.CognitiveServices/accounts` (This covers OpenAI).
   - **Resource**: Select your Azure OpenAI instance name.
   - **Target sub-resource**: Select `openai_account`.
6. **Virtual Network Tab**:
   - **Virtual network**: Select your VNet (e.g., `vnet-main`).
   - **Subnet**: Select your PE subnet (e.g., `snet-pe`).
   - **Private IP configuration**: Usually, "Dynamically allocate IP address" is sufficient.
7. **DNS Tab (CRITICAL)**:
   - **Integrate with private DNS zone**: Select **Yes**.
   - **Private DNS Zone**: It should automatically suggest `privatelink.openai.azure.com`. 
   - *Note: If you already have this zone, select it. If not, the portal will create it for you.*
8. **Review + Create**:
   - Verify the details and click **Create**. Wait for the deployment to finish (~2-5 minutes).

---

## 🔒 Step 2: Disable Public Access

Once the Private Endpoint is "Succeeded" and "Approved":

1. Go back to the **Networking** blade of your Azure OpenAI resource.
2. Under the **Firewalls and virtual networks** tab, change the setting to:
   - **Disabled** (or "Selected Networks" if you need to allow specific office IPs).
3. Click **Save**.

> [!WARNING]
> Setting this to **Disabled** will prevent all access from the public internet. Ensure your private connection is tested before enforcing this in production.

---

## 🌐 Step 3: Link Private DNS Zone to ACA VNet

If your Container App is in a **different VNet** than the Private Endpoint, you must link the Private DNS Zone to the ACA's VNet:

1. Search for **Private DNS zones** in the portal.
2. Select `privatelink.openai.azure.com`.
3. Under **Settings**, click **Virtual network links**.
4. Click **+ Add**.
5. Give it a name (e.g., `link-to-aca-vnet`) and select the VNet where your Container App resides.
6. Click **OK**.

---

## ✅ Step 4: Verification from Container App

To verify that your Container App is correctly using the Private Endpoint:

1. **Open ACA Console**:
   - Go to your **Container App** -> **Console** (under Monitoring).
2. **Run NSLOOKUP**:
   - Choose a container and run:
     ```bash
     nslookup <your-openai-name>.openai.azure.com
     ```
3. **Verify the Result**:
   - **SUCCESS**: If the result returns a **Private IP** (e.g., `10.0.x.x`).
   - **FAILURE**: If it returns a Public IP or fails to resolve.

### Example Success Output:
```text
Non-authoritative answer:
Name:    your-openai-name.openai.azure.com
Address: 10.0.1.5  <-- This should be your internal VNet IP
```

---

## 📂 Step 5: Manually Add DNS Record (Optional)

If the automatic registration didn't work, or if you need to add a custom record:

1. **Find your Private IP**:
   - Go to your **Private Endpoint** resource (`pe-openai-prod`).
   - On the **Overview** page, look for the **Network interface** link and click it.
   - Note down the **Private IP address** (e.g., `10.0.1.5`).
2. **Access the DNS Zone**:
   - Search for **Private DNS zones** and select `privatelink.openai.azure.com`.
3. **Add Record Set**:
   - Click **+ Record set** at the top.
4. **Configure the Record**:
   - **Name**: Enter your OpenAI resource name (without the `.openai.azure.com` part).
   - **Type**: Select `A - Address record`.
   - **TTL**: `1` (Hour).
   - **IP address**: Enter the Private IP you noted in step 1.
5. **Click OK**.

---

## 🛠️ Troubleshooting

| Issue | Potential Cause | Fix |
| :--- | :--- | :--- |
| **DNS resolves to Public IP** | Private DNS Zone not linked to VNet. | Check "Virtual network links" in the DNS Zone. |
| **403 Forbidden** | Public access disabled but PE not active. | Ensure PE status is "Approved" and matching the subnet. |
| **Connection Timeout** | Network Security Group (NSG) blocking traffic. | Ensure NSG on the PE subnet allows inbound traffic on port 443. |

> [!TIP]
> Always use the standard endpoint URL in your code: `https://<your-openai-name>.openai.azure.com/`. The Private DNS Zone will handle the translation to the private IP automatically.
