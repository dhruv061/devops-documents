# MongoDB 7.0.28 Self-Hosted Setup Guide

> **VM:** Azure Standard D8as v5 (8 vCPUs, 32 GiB RAM, 1TB P30)  
> **Port:** 57017 | **Replica Set:** artha-rs | **Public Access:** Enabled

---

## Quick Summary

| Step | What | Why |
|------|------|-----|
| 1 | Create data directory | MongoDB needs a place to store database files |
| 2 | Install MongoDB 7.0.28 | The database software itself |
| 3 | Configure MongoDB | Set port, paths, replica set name |
| 4 | System optimizations | Improve performance, prevent issues |
| 5 | Configure firewall | Allow MongoDB port through |
| 6 | Start MongoDB | Run the database service |
| 7 | Initialize replica set | Enable replica set features |
| 8 | Create admin user | Set up authentication |
| 9 | Enable security | Protect database from unauthorized access |
| 10 | Test connection | Verify everything works |

---

## Step 1: Create Data Directory

```bash
sudo mkdir -p /data/mongo
sudo mkdir -p /var/log/mongodb
```

**Why?** MongoDB needs directories to store:
- `/data/mongo` → Database files (collections, indexes)
- `/var/log/mongodb` → Log files for troubleshooting

---

## Step 2: Install MongoDB 7.0.28

```bash
# Import MongoDB GPG key (verifies package authenticity)
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

# Add MongoDB repository (tells apt where to download from)
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
   sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Update package list and install specific version
sudo apt update
sudo apt install -y mongodb-org=7.0.28 mongodb-org-database=7.0.28 \
   mongodb-org-server=7.0.28 mongodb-org-mongos=7.0.28 mongodb-org-tools=7.0.28

# Pin version (prevents accidental upgrades)
echo "mongodb-org hold" | sudo dpkg --set-selections
echo "mongodb-org-database hold" | sudo dpkg --set-selections
echo "mongodb-org-server hold" | sudo dpkg --set-selections
echo "mongodb-org-mongos hold" | sudo dpkg --set-selections
echo "mongodb-org-tools hold" | sudo dpkg --set-selections
```

**Why?**
- GPG key ensures you're downloading official MongoDB packages
- Specific version (7.0.28) for consistency
- Pinning prevents automatic upgrades that could break things

---

## Step 3: Set Directory Permissions

```bash
sudo chown -R mongodb:mongodb /data/mongo
sudo chown -R mongodb:mongodb /var/log/mongodb
```

**Why?** MongoDB runs as the `mongodb` user. It needs permission to read/write its directories.

---

## Step 4: Configure MongoDB

```bash
sudo nano /etc/mongod.conf
```

Replace with:

```yaml
# Where to store data
storage:
  dbPath: /data/mongo
  wiredTiger:
    engineConfig:
      cacheSizeGB: 16    # ~50% of 32GB RAM for optimal performance

# Where to write logs
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# Network settings
net:
  port: 57017           # Custom port (default is 27017)
  bindIp: 0.0.0.0       # Listen on all interfaces (allows public access)

# Timezone for logs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# Replica set configuration
replication:
  replSetName: artha-rs
```

**Why each setting?**

| Setting | Purpose |
|---------|---------|
| `dbPath` | Where database files are stored |
| `cacheSizeGB: 16` | Uses 16GB RAM for caching (faster queries) |
| `port: 57017` | Non-default port (slight security benefit) |
| `bindIp: 0.0.0.0` | Allows connections from any IP (needed for public access) |
| `replSetName` | Enables replica set features (durability, read preferences) |

---

## Step 5: System Optimizations

### Disable Transparent Huge Pages (THP)

```bash
sudo tee /etc/systemd/system/disable-thp.service > /dev/null <<EOF
[Unit]
Description=Disable Transparent Huge Pages
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable disable-thp
sudo systemctl start disable-thp
```

**Why?** THP causes memory issues with MongoDB. Disabling it improves performance.

### Set Process Limits

```bash
sudo tee /etc/security/limits.d/mongodb.conf > /dev/null <<EOF
mongodb soft nofile 64000
mongodb hard nofile 64000
mongodb soft nproc 64000
mongodb hard nproc 64000
EOF
```

**Why?** MongoDB needs to open many files and processes. Default limits are too low.

### Reduce Swappiness

```bash
echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Why?** Prevents Linux from swapping MongoDB data to disk (very slow).

---

## Step 6: Configure Firewall

```bash
sudo ufw enable
sudo ufw allow 22/tcp      # SSH (don't lock yourself out!)
sudo ufw allow 57017/tcp   # MongoDB
sudo ufw status
```

**Why?** 
- UFW blocks unwanted traffic
- Allow SSH so you can still connect
- Allow MongoDB port for database connections

### Azure NSG (Network Security Group)

In Azure Portal → VM → Networking → Add inbound rule:

| Field | Value |
|-------|-------|
| Destination port ranges | 57017 |
| Protocol | TCP |
| Action | Allow |
| Name | Allow-MongoDB-57017 |

**Why?** Azure has its own firewall. Both UFW and NSG must allow the port.

---

## Step 7: Start MongoDB

```bash
sudo systemctl start mongod
sudo systemctl enable mongod    # Start on boot
sudo systemctl status mongod    # Verify it's running
```

**Why?** 
- `start` runs MongoDB now
- `enable` makes it start automatically after reboot

---

## Step 8: Initialize Replica Set

```bash
mongosh --port 57017
```

Run inside mongosh:

```javascript
// Initialize with private IP (MongoDB needs to recognize itself)
rs.initiate({
  _id: "artha-rs",
  members: [
    { _id: 0, host: "10.0.0.4:57017" }
  ]
})

// Wait 5-10 seconds, then verify
rs.status()
```

**Why replica set for single node?**
- Enables oplog (operation log) for change streams
- Required for transactions
- Required for some backup tools
- Easy to add more nodes later

---

## Step 9: Create Admin User

Still in mongosh:

```javascript
use admin

db.createUser({
  user: "admin",
  pwd: "YourSecurePassword123!",
  roles: [
    { role: "root", db: "admin" },
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "clusterAdmin", db: "admin" }
  ]
})

exit
```

**Why these roles?**

| Role | Permission |
|------|------------|
| `root` | Full admin access |
| `userAdminAnyDatabase` | Create/manage users on any database |
| `readWriteAnyDatabase` | Read/write data on any database |
| `dbAdminAnyDatabase` | Create indexes, view stats on any database |
| `clusterAdmin` | Manage replica set |

---

## Step 10: Enable Security

### Generate Keyfile

```bash
openssl rand -base64 756 | sudo tee /etc/mongodb-keyfile > /dev/null
sudo chmod 400 /etc/mongodb-keyfile
sudo chown mongodb:mongodb /etc/mongodb-keyfile
```

**Why?**
- Keyfile authenticates replica set members to each other
- `chmod 400` → Only owner can read (MongoDB requires this)

### Update Config

```bash
sudo nano /etc/mongod.conf
```

Add at the end:

```yaml
security:
  authorization: enabled
  keyFile: /etc/mongodb-keyfile
```

### Restart MongoDB

```bash
sudo systemctl restart mongod
sudo systemctl status mongod
```

**Why security?**

| Without Security | With Security |
|------------------|---------------|
| Anyone can connect | Password required |
| Anyone can delete data | Only authorized users |
| Bots can steal/ransom data | Protected from attacks |

---

## Step 11: Test Connections

### Local Connection

```bash
# Without credentials (should fail to see databases)
mongosh --port 57017
> show dbs
# Error: requires authentication

# With credentials (should work)
mongosh "mongodb://admin:YourSecurePassword123!@localhost:57017/admin?authSource=admin&directConnection=true"
> show dbs
# Shows databases ✅
```

### Remote Connection

```bash
mongosh "mongodb://admin:YourSecurePassword123!@20.244.50.192:57017/admin?authSource=admin&directConnection=true"
```

---

## Connection String Format

```
mongodb://USERNAME:PASSWORD@PUBLIC_IP:57017/DATABASE?authSource=admin&directConnection=true
```

Example:
```
mongodb://admin:YourSecurePassword123!@20.244.50.192:57017/mydb?authSource=admin&directConnection=true
```

---

## Why `directConnection=true`?

The replica set is configured with **private IP (10.0.0.4)**.

When clients connect:
1. MongoDB says: "My replica set members are at 10.0.0.4"
2. Client tries to connect to 10.0.0.4 → **Fails** (not reachable externally)

`directConnection=true` tells the client: "Don't ask for replica set members, just connect directly."

---

## Verification Commands

```bash
# Check MongoDB version
mongod --version

# Check service status
sudo systemctl status mongod

# Check port is listening
sudo ss -tlnp | grep 57017

# View logs
sudo tail -f /var/log/mongodb/mongod.log

# Check replica set status (in mongosh)
rs.status()

# Check disk usage
df -h /data/mongo
```

---

## Important File Locations

| File | Purpose |
|------|---------|
| `/etc/mongod.conf` | MongoDB configuration |
| `/data/mongo` | Database files |
| `/var/log/mongodb/mongod.log` | Log file |
| `/etc/mongodb-keyfile` | Replica set authentication key |

---

## Troubleshooting

### MongoDB won't start

```bash
# Check logs
sudo tail -50 /var/log/mongodb/mongod.log

# Check config syntax
mongod --config /etc/mongod.conf --validate

# Common issues:
# - Wrong permissions on /data/mongo or keyfile
# - Invalid YAML in config file
# - Port already in use
```

### Can't connect remotely

1. Check Azure NSG allows port 57017
2. Check UFW allows port 57017
3. Check MongoDB is listening on 0.0.0.0:
   ```bash
   sudo ss -tlnp | grep 57017
   # Should show: 0.0.0.0:57017
   ```

### Authentication failed

```bash
# Connect locally without auth to check/reset user
# Temporarily disable auth in config, restart, fix user, re-enable
```

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONGODB QUICK REFERENCE                       │
├─────────────────────────────────────────────────────────────────┤
│  Start:    sudo systemctl start mongod                          │
│  Stop:     sudo systemctl stop mongod                           │
│  Restart:  sudo systemctl restart mongod                        │
│  Status:   sudo systemctl status mongod                         │
│  Logs:     sudo tail -f /var/log/mongodb/mongod.log             │
├─────────────────────────────────────────────────────────────────┤
│  Config:   /etc/mongod.conf                                     │
│  Data:     /data/mongo                                          │
│  Keyfile:  /etc/mongodb-keyfile                                 │
├─────────────────────────────────────────────────────────────────┤
│  Connect (local):                                                │
│  mongosh "mongodb://admin:PASS@localhost:57017/admin             │
│           ?authSource=admin&directConnection=true"               │
│                                                                  │
│  Connect (remote):                                               │
│  mongosh "mongodb://admin:PASS@PUBLIC_IP:57017/admin             │
│           ?authSource=admin&directConnection=true"               │
└─────────────────────────────────────────────────────────────────┘
```

---

**Document Created:** January 15, 2026  
**MongoDB Version:** 7.0.28  
**OS:** Ubuntu 22.04/24.04
