# Per-Server Docker Log Dashboards

Create one log dashboard per server. Each shows only that server's containers in a dropdown.

---

## Part 1: Alloy Config (Per Server)

Each server needs the **log collection** section enabled with a **unique `job` name**.

### Example: Dev Server (`artha-dev-server`)
```hcl
// --- METRICS (already working) ---
prometheus.exporter.unix "local_system" { }

prometheus.scrape "scrape_metrics" {
  targets         = prometheus.exporter.unix.local_system.targets
  forward_to      = [prometheus.relabel.filter_metrics.receiver]
  scrape_interval = "15s"
}

prometheus.relabel "filter_metrics" {
  rule {
    target_label = "job"
    replacement  = "artha-dev-server"  // <-- UNIQUE per server
  }
  forward_to = [prometheus.remote_write.metrics_service.receiver]
}

// --- LOGS (ADD THIS) ---
discovery.docker "linux_containers" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.linux_containers.targets
  forward_to = [loki.process.add_log_labels.receiver]
}

loki.process "add_log_labels" {
  stage.static_labels {
    values = {
      job = "artha-dev-server",  // <-- SAME as metrics job above
    }
  }
  forward_to = [loki.write.central_server.receiver]
}

// --- DESTINATIONS ---
prometheus.remote_write "metrics_service" {
  endpoint {
    url = "https://prometheus.arthajobboard.com/api/v1/write"
  }
}

loki.write "central_server" {
  endpoint {
    url = "https://loki.arthajobboard.com/loki/api/v1/push"
  }
}
```

### For Other Servers - Just Change the Job Name:

| Server | `job` value |
|--------|-------------|
| Dev Server | `artha-dev-server` |
| Prod Server | `artha-prod-server` |
| DB Server | `artha-dev-db-server` |
| Central Services | `artha-central-services` |

After updating each server's config, restart Alloy:
```bash
sudo systemctl restart alloy
```

---

## Part 2: Create One Dashboard Per Server

Repeat these steps for each server.

### A. Create the Dashboard
1. Go to **Dashboards → New → Dashboard**.
2. Click **Dashboard Settings** (gear icon).
3. Set the **Title** (e.g., `Dev Server Logs`).

### B. Add the Container Dropdown Variable
1. In Settings, go to **Variables → Add variable**.
2. Configure:
   - **Name**: `container`
   - **Type**: `Query`
   - **Label**: `Container`
   - **Data source**: Select your **Loki** datasource
   - **Query**: 
     ```logql
     label_values({job="artha-dev-server"}, container_name)
     ```
     *(Change `artha-dev-server` to match each server's job name)*
   - **Selection Options**: Enable **Multi-value** and **Include All option**
3. Click **Apply**.

### C. Add the Logs Panel
1. Click **Add → Visualization**.
2. Select **Loki** as the Data Source.
3. Enter this query:
   ```logql
   {job="artha-dev-server", container_name=~"$container"}
   ```
   *(Change `artha-dev-server` to match)*
4. Change **Visualization type** to **Logs** (right sidebar).
5. **Panel Title**: `Logs: $container`
6. Enable **Options → Wrap lines** for better readability.
7. Click **Apply** and **Save Dashboard**.

---

## Part 3: Using the Dashboard

| Feature | How |
|---------|-----|
| **Select Container** | Use the `Container` dropdown at the top |
| **Search Logs** | Type in the search bar above the log panel |
| **Filter by Time** | Use the Grafana time picker (top right) |
| **Filter by keyword** | Update query to: `{job="artha-dev-server", container_name=~"$container"} \|= "error"` |
| **Multiple Containers** | Select multiple from the dropdown (Multi-value enabled) |

---

## Quick Reference: Dashboard Per Server

| Dashboard Name | Loki Query |
|----------------|------------|
| Dev Server Logs | `{job="artha-dev-server", container_name=~"$container"}` |
| Prod Server Logs | `{job="artha-prod-server", container_name=~"$container"}` |
| DB Server Logs | `{job="artha-dev-db-server", container_name=~"$container"}` |
| Central Services Logs | `{job="artha-central-services", container_name=~"$container"}` |
