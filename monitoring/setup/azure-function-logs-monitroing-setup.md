# Azure Functions Log Monitoring: Complete Setup Guide

This guide covers everything from the initial Azure Service Principal setup to verifying logs in Explore and configuring the final Grafana dashboard.

---

## Part 1: Azure Side (Prerequisites)

### Step 1: Create a Service Principal
1.  Go to **Azure Portal** -> **Microsoft Entra ID** (formerly Azure AD).
2.  Select **App registrations** -> **New registration**.
3.  Name: `grafana-monitoring-sp`.
4.  Supported account types: **Accounts in this organizational directory only**.
5.  Click **Register**. Note down the **Application (client) ID** and **Directory (tenant) ID**.

### Step 2: Create a Client Secret
1.  In the app you just created, go to **Certificates & secrets** -> **Client secrets** -> **New client secret**.
2.  Description: `Grafana Monitoring`.
3.  Expires: `730 days`.
4.  Click **Add**. **IMPORTANT**: Copy the **Value** immediately. You will not see it again.

### Step 3: Assign RBAC Roles (Subscription Level)
For Grafana to query logs and populate dropdowns, you must grant permissions at the **Subscription level**.
1.  Go to your **Subscription** -> **Access control (IAM)**.
2.  Click **Add** -> **Add role assignment**.
3.  Search for and assign the following **3 roles** to your Service Principal:
    - **Reader**: Required for the resource dropdown to populate in Grafana.
    - **Monitoring Reader**: Required for metrics data.
    - **Log Analytics Reader**: Required for reading the actual log data.
4.  For each role: Click **+ Select members**, search for `grafana-monitoring-sp`, and click **Review + assign**.

---

## Part 2: Testing & Resource Discovery (Explore Section)

Before importing the dashboard, you must verify that Grafana can "see" your Azure logs and find the exact path for your resources.

1.  Open **Grafana** and click the **Explore** icon in the sidebar.
2.  Select your **Azure Monitor** data source.
3.  Under the **Service** dropdown, select **Logs** (Azure Log Analytics).
4.  Select your **Subscription** and **Resource Group**.
5.  **Find the Full Resource ID**: 
    - In the **Resource** dropdown, select your Application Insights instance.
    - Run a simple query: `traces | take 5`.
    - Click on the **Query Inspector** button (near the "Run query" button).
    - Look for the request URL or metadata showing the resource path. It will look like this:
      `/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/microsoft.insights/components/<app-name>`
    - **Copy this full path**. You need it for the dashboard variables.

---

## Part 3: Dashboard Setup

### Step 1: Import Dashboard
1.  Download [AZURE_FUNCTIONS_DASHBOARD.json](file:///home/artha-devops-dhruv/Desktop/Repo's/monitoring/dashboards/AZURE_FUNCTIONS_DASHBOARD.json).
2.  Go to **Dashboards** -> **New** -> **Import**.
3.  Upload the JSON and select your **Azure Monitor** data source.

### Step 2: Configure Variable (Friendly Names)
This step makes the dashboard dropdown look professional (showing `sls-prod` instead of a 200-character ID).

1.  In the dashboard, go to **Dashboard Settings** -> **Variables**.
2.  Click on the variable named `app_insights_id`.
3.  In the **Values** (Custom options) box, enter your resources using the `Label : Value` syntax.
4.  **Adding Multiple Resources**:
    - If you have more than one Application Insights instance, you must put them on **one single line**, separated by a **comma**.
    - Format: `Name1 : ID1, Name2 : ID2, Name3 : ID3`
    - **Example**:
      ```text
      sls-prod : /subscriptions/ccf1.../components/sls-artha-prod, sls-dev : /subscriptions/ccf1.../components/sls-artha-dev, sls-qa : /subscriptions/ccf1.../components/sls-artha-qa
      ```
5.  Click **Apply** and **Save Dashboard**.

---

## Part 4: Query Reference

The dashboard uses the following optimized KQL query to provide colors and chronological sorting:

```kusto
traces
| where $__timeFilter(timestamp)
| where '$search' == '' or message contains '$search'
| extend level = case(
    severityLevel == 0, 'trace',
    severityLevel == 1, 'info',
    severityLevel == 2, 'warning',
    severityLevel == 3, 'error',
    'info'
)
| project timestamp, message, level, operation_Name
| order by timestamp asc
```

---

## Usage Tips
- **Real-time Streaming**: Set the dashboard refresh to **3s**.
- **Auto-Follow**: Click the **Down Arrow** (↓) in the log panel header to auto-scroll to latest logs.
- **Search**: Use the **Search Logs** box at the top to filter by specific keywords.
