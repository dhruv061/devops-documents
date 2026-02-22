# Monitoring Agents: Master Setup Guide (AKS & VMs)

This document provides the exhaustive, step-by-step instructions to install and configure **Grafana Alloy** as your unified agent for metrics and logs.

## Part 1: AKS Cluster Agent (Helm)

### 1.1. Prerequisites
- `kubectl` connected to your AKS cluster.
- `helm` installed.
- The IP address of your **Central Monitoring Server**.

### 1.2. Deploy Alloy
```bash
# Add Grafana repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create the values.yaml file
cat <<EOF > alloy-values.yaml
alloy:
  configReloader:
    enabled: true
  config: |
    // 1. DISCOVERY: Find all Kubernetes pods
    discovery.kubernetes "pods" {
      role = "pod"
    }

    // 2. METRICS: Scrape Pod targets
    prometheus.scrape "kubernetes_pods" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [prometheus.remote_write.central_server.receiver]
    }

    // 3. LOGS: Collect Container logs
    loki.source.kubernetes "pod_logs" {
      targets    = discovery.kubernetes.pods.targets
      forward_to = [loki.write.central_server.receiver]
    }

    // 4. DESTINATION: Push to Central Server
    prometheus.remote_write "central_server" {
      endpoint {
        url = "http://<CENTRAL_SERVER_IP>:9090/api/v1/write"
      }
    }

    loki.write "central_server" {
      endpoint {
        url = "http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push"
      }
    }
EOF

# IMPORTANT: Update <CENTRAL_SERVER_IP> in alloy-values.yaml manually before running next command!

# Install via Helm
helm install alloy grafana/alloy -f alloy-values.yaml --namespace monitoring --create-namespace
```

---

## Part 2: Ubuntu VM Agent (Systemd)

### 2.1. Initial Setup & Installation
Run these commands as `azureuser` on your standalone Ubuntu VMs.

```bash
# Add Grafana GPG key
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

# Add Grafana repository
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Update and install Alloy
sudo apt-get update
sudo apt-get install -y alloy
```

### 2.2. Permissions Configuration
Ensure `azureuser` can manage the config and Alloy can read Docker logs.

```bash
# Allow azureuser to edit configs
sudo usermod -aG alloy azureuser

# Allow Alloy to read Docker socket
sudo usermod -aG docker alloy

# Restart Docker to apply group changes
sudo systemctl restart docker
```

### 2.3. Create Configuration (`/etc/alloy/config.alloy`)

This configuration follows the **Official Grafana Alloy Tutorial** for sending metrics to Prometheus, while adding your specific `job` and `environment` labels.

**Command:**
```bash
cat <<EOF | sudo tee /etc/alloy/config.alloy
// 1. METRICS: Official Tutorial Pattern
prometheus.exporter.unix "local_system" {}

prometheus.scrape "scrape_metrics" {
  targets         = prometheus.exporter.unix.local_system.targets
  forward_to      = [prometheus.relabel.filter_metrics.receiver]
  scrape_interval = "15s"
}

// Add/Filter Labels
prometheus.relabel "filter_metrics" {
  rule {
    target_label = "job"
    replacement  = "artha-dev-server" // <-- CHANGE THIS per VM
  }
  rule {
    target_label = "environment"
    replacement  = "dev"              // <-- CHANGE THIS per VM
  }
  forward_to = [prometheus.remote_write.metrics_service.receiver]
}

// 2. LOGS: Discovery and Labeling
discovery.docker "linux_containers" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "docker_log_labeling" {
  targets = discovery.docker.linux_containers.targets

  // Map internal docker name to visible "container_name" label
  rule {
    source_labels = ["__meta_docker_container_name"]
    target_label  = "container_name"
  }
  
  // Clean up leading slash in container name
  rule {
    source_labels = ["container_name"]
    regex         = "/(.*)"
    target_label  = "container_name"
  }
}

loki.source.docker "docker_logs" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.docker_log_labeling.output
  forward_to = [loki.process.add_log_labels.receiver]
}

loki.process "add_log_labels" {
  stage.static_labels {
    values = {
      job         = "artha-dev-server", // <-- CHANGE THIS per VM
      environment = "dev",              // <-- CHANGE THIS per VM
    }
  }
  forward_to = [loki.write.central_server.receiver]
}

// 3. DESTINATION: Push to Central Server
prometheus.remote_write "metrics_service" {
  endpoint {
    url = "http://<CENTRAL_SERVER_IP>:9090/api/v1/write"
  }
}

loki.write "central_server" {
  endpoint {
    url = "http://<CENTRAL_SERVER_IP>:3100/loki/api/v1/push"
  }
}
EOF
```

### 2.4. Start and Verify
```bash
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy

# Verify status
sudo systemctl status alloy

# View real-time logs to see data being pushed
sudo journalctl -u alloy -f
```

---

## Part 3: Verification in Grafana

1. Login to Grafana (`http://<CENTRAL_IP>:3000`).
2. Go to **Explore**.
3. Select **Loki** as the source:
   - Try query: `{job="pod_logs"}` or `{job="docker_logs"}`.
4. Select **Prometheus** as the source:
   - Try query: `node_cpu_seconds_total` or `up`.
   - You should see your VM names and K8s node names in the results.
