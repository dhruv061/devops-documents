# AKS Infrastructure Monitoring Setup

This guide documents the comprehensive monitoring solution for the AKS cluster, centralizing all metrics and logs on a dedicated VM.

## Architecture Overview

We use a **Hybrid Monitoring Strategy** to balance standard features with high-performance log collection:

| Data Type | Tool | Method | Destination |
| :--- | :--- | :--- | :--- |
| **Metrics** | `kube-prometheus-stack` | Remote Write | Central Prometheus (Port 9090) |
| **Logs** | `Grafana Alloy` | Kubernetes API | Central Loki (Port 3100) |
| **Azure Functions** | `Azure Monitor` | KQL (App Insights) | Central Grafana (Direct) |

---

## Prerequisites

- **Central VM IP**: `10.0.2.4`
- **Namespace**: `monitoring` (for agents), `artha` (for apps)
- **Cluster Name**: `artha-aks-cluster`

---

## Step 1: Metrics Setup (`kube-prometheus-stack`)

We use the community-standard Prometheus stack but disable local storage/UI to save AKS resources.

### Configuration (`prometheus-values.yaml`)
- **Node Exporter**: Enabled (Node metrics).
- **Kube-State-Metrics**: Enabled (Pod/Deployment/Node status).
- **Remote Write**: Configured to send data to `http://10.0.2.4:9090/api/v1/write`.
- **Grafana/Alertmanager**: Disabled locally (using Central VM instead).

### Installation
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install k8s-prometheus prometheus-community/kube-prometheus-stack \
  -f prometheus-values.yaml \
  -n monitoring --create-namespace
```

---

## Step 2: Logs Setup (`Grafana Alloy`)

We use Grafana Alloy running as a **DaemonSet** for cluster-wide log visibility.

### Key Logic
- **Discovery**: Find all pods in the cluster.
- **Relabeling**: 
  - Extracts the **Deployment** name by stripping hashes from ReplicaSets.
  - Corrected extraction for **StatefulSets** (keeps full name).
  - Explicitly adds `cluster="artha-aks-cluster"` and `namespace`/`pod` labels.
- **Collection**: uses `loki.source.kubernetes` to tail logs via the Kubernetes API.

### Installation
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install alloy-logs grafana/alloy \
  -f alloy-logs-values.yaml \
  -n monitoring
```

---

## Features & Dashboards

### Smart Labeling
The setup automatically provides high-level filtering labels:
- `cluster`: Hardcoded to the cluster name.
- `deployment`: Unified label for Deployments/StatefulSets (Service-centric view).
- `namespace`: Kubernetes namespace.

### Centralized Visibility
Import the following JSON files into your central Grafana:
1. **[AKS_LOGS_DASHBOARD.json](./dashboards/AKS_LOGS_DASHBOARD.json)**: Optimized for AKS logs with dynamic cluster/deployment filtering.
2. **Dashboard 15661**: Standard Kubernetes Cluster monitoring for metrics.

---

## Verification

### Check Metrics
In Central Grafana (Prometheus), query:
`count({cluster="artha-aks-cluster"})`

### Check Logs
In Central Grafana (Loki/Explore), query:
`{cluster="artha-aks-cluster", deployment="admin"}`
