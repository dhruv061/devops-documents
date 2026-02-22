# Central Monitoring Server: Master Setup Guide

This document provides absolute, step-by-step instructions to configure your Central Monitoring Server on Ubuntu using the `azureuser` account.

## Prerequisites
- Ubuntu Server 22.04+
- `azureuser` with sudo privileges
- Inbound ports open: `9090` (Prometheus), `3100` (Loki), `3000` (Grafana)

---

## 1. Prometheus Installation (Metrics)

### 1.1. Prepare Directories
```bash
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown -R azureuser:azureuser /etc/prometheus /var/lib/prometheus
```

### 1.2. Download & Install Binaries (v3.9.1)
```bash
cd /tmp
curl -LO https://github.com/prometheus/prometheus/releases/download/v3.9.1/prometheus-3.9.1.linux-amd64.tar.gz
tar -xvf prometheus-3.9.1.linux-amd64.tar.gz
cd prometheus-3.9.1.linux-amd64

sudo cp prometheus promtool /usr/local/bin/
sudo cp -r consoles console_libraries /etc/prometheus/

# Ensure correct permissions
sudo chown azureuser:azureuser /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod +x /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chown -R azureuser:azureuser /etc/prometheus /var/lib/prometheus
```

### 1.3. Service Configuration (`/etc/prometheus/prometheus.yml`)
```bash
cat <<EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
sudo chown azureuser:azureuser /etc/prometheus/prometheus.yml
```

### 1.4. Systemd Service Setup
```bash
cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=azureuser
Group=azureuser
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.enable-remote-write-receiver

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

---

## 2. Loki Installation (Logs)

### 2.1. Download & Install Binaries (v3.6.5)
```bash
cd /tmp
curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 | wget -qi -
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki

# CRITICAL: Ensure executable permissions (Fixes 203/EXEC error)
sudo chown azureuser:azureuser /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki

sudo mkdir -p /etc/loki /var/lib/loki
sudo chown -R azureuser:azureuser /etc/loki /var/lib/loki
```

### 2.2. Service Configuration (`/etc/loki/local-config.yaml`)
```bash
cat <<EOF | sudo tee /etc/loki/local-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 0.0.0.0
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /var/lib/loki/storage

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: true
EOF
sudo chown azureuser:azureuser /etc/loki/local-config.yaml
```

### 2.3. Systemd Service Setup
```bash
cat <<EOF | sudo tee /etc/systemd/system/loki.service
[Unit]
Description=Loki service
After=network.target

[Service]
Type=simple
User=azureuser
Group=azureuser
ExecStart=/usr/local/bin/loki -config.file /etc/loki/local-config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now loki
```

---

## 3. Grafana Installation (UI)

### 3.1. Install Grafana OSS
```bash
sudo apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/apt stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl enable --now grafana-server
```

### 3.2. Verification
1. Open Browser: `http://<YOUR_SERVER_IP>:3000`
2. Default Login: `admin` / `admin`
3. Check Prometheus: `http://<YOUR_SERVER_IP>:9090`
4. Check Loki: `http://<YOUR_SERVER_IP>:3100/ready`
