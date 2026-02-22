# Elasticsearch + Kibana — Complete Setup Guide (No Server Crash)

> **Why servers crash with Elasticsearch:**
> 1. `vm.max_map_count` not set (ES needs 262144, Linux default is 65530)
> 2. No memory limit on container → ES eats all RAM → OOM killer kills everything
> 3. Swap enabled → ES does garbage collection storms → server freezes
> 4. JVM heap too large (>50% of container memory) → no room for Lucene file cache
> 5. No log rotation → disk fills up → server dies

This guide fixes ALL of these.

---

## Prerequisites

- Ubuntu/Debian VM (Azure/AWS/GCP)
- Minimum **4 GB RAM** (8 GB+ recommended)
- Docker installed
- SSH access with sudo/root

---

## Step 1: Check VM Resources

```bash
# Check total RAM
free -h

# Check disk space (need at least 20 GB free)
df -h /

# Check CPU cores
nproc
```

**Note down your total RAM** — you'll need it for Step 5.

---

## Step 2: Set Kernel Parameters (CRITICAL — #1 Crash Cause)

Elasticsearch requires `vm.max_map_count` to be at least `262144`. Without this, ES will either crash on startup or crash under load.

```bash
# Set it immediately
sudo sysctl -w vm.max_map_count=262144
```

**Make it permanent (survives reboot):**

```bash
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

**Verify:**

```bash
sysctl vm.max_map_count
# Output should be: vm.max_map_count = 262144
```

---

## Step 3: Disable Swap (CRITICAL — #2 Crash Cause)

Swap causes Elasticsearch garbage collection storms which freeze the server.

```bash
# Disable swap immediately
sudo swapoff -a

# Make it permanent — comment out swap lines in fstab
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
```

**Verify:**

```bash
free -h
# Swap line should show 0B for total
```

---

## Step 4: Install Docker (Skip if Already Installed)

```bash
# Check if Docker is installed
docker --version
```

**If not installed:**

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin

# Enable Docker to start on boot
sudo systemctl enable docker
sudo systemctl start docker

# Add your user to docker group (optional, avoids sudo for docker commands)
sudo usermod -aG docker $USER

# Verify
docker --version
docker compose version
```

---

## Step 5: Calculate Memory Limits for Your VM

Use this table to set safe memory limits based on your VM's total RAM:

| VM RAM | ES Container Limit (`mem_limit`) | ES JVM Heap (`-Xms` / `-Xmx`) | Kibana Limit | Free for OS |
|--------|----------------------------------|-------------------------------|--------------|-------------|
| 4 GB   | `2g`                             | `1g`                          | `1g`         | ~1 GB       |
| 8 GB   | `5g`                             | `2g`                          | `1g`         | ~2 GB       |
| 16 GB  | `10g`                            | `5g`                          | `1g`         | ~5 GB       |
| 32 GB  | `20g`                            | `10g`                         | `2g`         | ~10 GB      |
| 64 GB  | `38g`                            | `16g`                         | `2g`         | ~24 GB      |

### Rules:
- **ES JVM Heap** must be ≤ **50%** of container memory limit
- **ES JVM Heap** must NEVER exceed **31g** (compressed oops limit)
- Always leave **at least 2 GB** for the OS
- `mem_limit` and `memswap_limit` must be the **same** value (prevents swap use)

---

## Step 6: Create Directory Structure

```bash
sudo mkdir -p /opt/elasticsearch/config
cd /opt/elasticsearch
```

---

## Step 7: Create `elasticsearch.yml`

```bash
sudo nano /opt/elasticsearch/config/elasticsearch.yml
```

Paste this content:

```yaml
# ============================================================
# Elasticsearch Configuration
# ============================================================
cluster.name: dev-artha-es-cluster
node.name: dev-node-1
discovery.type: single-node

network.host: 0.0.0.0
http.port: 9200

# Security
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

---

## Step 8: Create `docker-compose.yml`

```bash
sudo nano /opt/elasticsearch/docker-compose.yml
```

Paste the content below. **Replace `<ES_HEAP>` and `<CONTAINER_MEM>` and `<KIBANA_MEM>` with values from the Step 5 table based on your VM RAM.**

For example, if your VM has **16 GB RAM**, use `ES_HEAP=5g`, `CONTAINER_MEM=10g`, `KIBANA_MEM=1g`.

```yaml
version: "3.9"

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:9.0.0
    container_name: elasticsearch-dev
    restart: unless-stopped

    environment:
      node.name: dev-node-1
      cluster.name: dev-artha-es-cluster
      discovery.type: single-node
      xpack.security.enabled: "true"
      xpack.security.http.ssl.enabled: "false"
      xpack.security.transport.ssl.enabled: "false"
      bootstrap.memory_lock: "true"
      # ⚠️ REPLACE <ES_HEAP> with value from Step 5 table
      ES_JAVA_OPTS: "-Xms<ES_HEAP> -Xmx<ES_HEAP>"

    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536

    volumes:
      - es-data:/usr/share/elasticsearch/data
      - es-logs:/usr/share/elasticsearch/logs
      - ./config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro

    ports:
      - "9200:9200"

    # ⚠️ REPLACE <CONTAINER_MEM> with value from Step 5 table
    mem_limit: <CONTAINER_MEM>
    memswap_limit: <CONTAINER_MEM>

    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

  kibana:
    image: docker.elastic.co/kibana/kibana:9.0.0
    container_name: kibana-dev
    restart: unless-stopped

    environment:
      ELASTICSEARCH_HOSTS: "http://elasticsearch:9200"
      ELASTICSEARCH_USERNAME: "kibana_system"
      ELASTICSEARCH_PASSWORD: "CHANGE_ME_AFTER_STEP_10"
      xpack.security.encryptionKey: "Yy8wQ2y7bP3rD1kL0sF6vU9tH4Zabc12"
      xpack.encryptedSavedObjects.encryptionKey: "Q1weR2uI8oP6lK7zD5mN0xC3yV9Babc12"
      xpack.reporting.encryptionKey: "A1sdF3gH7jK2lM8qW5vZ0bC6nR4Tabc12"
      SERVER_NAME: kibana-dev

    ports:
      - "5601:5601"

    depends_on:
      elasticsearch:
        condition: service_healthy

    # ⚠️ REPLACE <KIBANA_MEM> with value from Step 5 table
    mem_limit: <KIBANA_MEM>
    memswap_limit: <KIBANA_MEM>

    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "3"

volumes:
  es-data:
    driver: local
  es-logs:
    driver: local
```

Save and exit.

---

## Step 9: Set File Permissions

```bash
# ES runs as UID 1000 inside the container
sudo chown -R 1000:1000 /opt/elasticsearch/config
```

---

## Step 10: Start Elasticsearch

```bash
cd /opt/elasticsearch
sudo docker compose up -d
```

**Wait for ES to become healthy (~60–90 seconds):**

```bash
# Watch container status — wait until health shows "healthy"
sudo docker ps

# Or watch logs
sudo docker logs -f elasticsearch-dev
```

**Check ES is running:**

```bash
curl http://localhost:9200
```

You should see a JSON response with cluster info.

---

## Step 11: Set Passwords (Security Enabled)

Since `xpack.security.enabled: true`, you must set passwords.

### Set `elastic` superuser password:

```bash
sudo docker exec -it elasticsearch-dev /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

Enter your desired password when prompted. **Save this password — you'll use it to login to Kibana.**

### Set `kibana_system` password:

```bash
sudo docker exec -it elasticsearch-dev /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

Enter your desired password. **You'll need this for the next step.**

---

## Step 12: Update Kibana Password in docker-compose.yml

Edit the compose file:

```bash
sudo nano /opt/elasticsearch/docker-compose.yml
```

Find this line under the `kibana` service:

```yaml
ELASTICSEARCH_PASSWORD: "CHANGE_ME_AFTER_STEP_10"
```

Replace `CHANGE_ME_AFTER_STEP_10` with the `kibana_system` password you set in Step 11.

Save and restart Kibana:

```bash
cd /opt/elasticsearch
sudo docker compose up -d
```

---

## Step 13: Verify Everything Works

### Check cluster health:

```bash
curl -u elastic:<YOUR_ELASTIC_PASSWORD> http://localhost:9200/_cluster/health?pretty
```

Expected output — `status` should be `green` or `yellow`:

```json
{
  "cluster_name" : "dev-artha-es-cluster",
  "status" : "green",
  "number_of_nodes" : 1
}
```

### Check container memory usage:

```bash
sudo docker stats --no-stream
```

Verify ES is NOT exceeding its memory limit.

### Access Kibana:

Open in browser: `http://<VM-IP>:5601`

Login with:
- **Username:** `elastic`
- **Password:** the password you set in Step 11

---

## Step 14: Verify Crash Protection

Run these checks to confirm your server won't crash:

```bash
# 1. Kernel setting is correct
sysctl vm.max_map_count
# Expected: 262144

# 2. Swap is off
free -h | grep Swap
# Expected: 0B total

# 3. Memory limits are enforced
sudo docker inspect elasticsearch-dev | grep -i memory
# Should show your mem_limit value

# 4. Logs are rotating (won't fill disk)
sudo docker inspect elasticsearch-dev | grep -A5 LogConfig
# Should show max-size: 50m, max-file: 3
```

---

## Troubleshooting

### ES container keeps restarting

```bash
sudo docker logs elasticsearch-dev --tail 50
```

| Error | Fix |
|-------|-----|
| `max virtual memory areas vm.max_map_count [65530] is too low` | Run Step 2 again |
| `memory locking requested for elasticsearch process but memory is not locked` | Check `ulimits` and `bootstrap.memory_lock` in compose |
| `java.lang.OutOfMemoryError: Java heap space` | Reduce `ES_JAVA_OPTS` heap size |
| Container killed by OOM | Increase `mem_limit` or reduce heap |

### Kibana shows "Kibana server is not ready yet"

- Wait 2-3 minutes — Kibana takes time to start
- Check ES is healthy first: `curl http://localhost:9200`
- Check Kibana logs: `sudo docker logs kibana-dev --tail 50`

### Server running slow

```bash
# Check what's using memory
sudo docker stats --no-stream

# Check system memory
free -h

# Check disk I/O
iostat -x 1 5
```

---

## Useful Commands

| Command | Purpose |
|---------|---------|
| `sudo docker compose up -d` | Start all services |
| `sudo docker compose down` | Stop all services (data preserved) |
| `sudo docker compose restart` | Restart all services |
| `sudo docker compose logs -f` | Follow all logs |
| `sudo docker stats` | Live memory/CPU usage |
| `curl localhost:9200/_cat/indices?v` | List all indices |
| `curl localhost:9200/_cluster/health?pretty` | Cluster health |
| `sudo docker compose down -v` | ⚠️ DANGER: Stop & DELETE all data |

---

## What This Setup Does to Prevent Crashes

| Protection | How |
|------------|-----|
| **OOM Prevention** | `mem_limit` + `memswap_limit` hard-cap container memory |
| **Kernel Crash Prevention** | `vm.max_map_count=262144` set permanently |
| **Swap Storm Prevention** | Swap disabled system-wide + `memswap_limit` = `mem_limit` |
| **Disk Full Prevention** | Log rotation with `max-size: 50m`, `max-file: 3` |
| **Auto Recovery** | `restart: unless-stopped` + health checks |
| **Memory Lock** | `bootstrap.memory_lock: true` + `ulimits.memlock` unlimited |
| **Kibana Dependency** | Kibana waits for ES health check before starting |
