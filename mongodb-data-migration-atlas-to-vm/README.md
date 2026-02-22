# MongoDB Migration Scripts - Documentation

## Quick Start

```bash
# 1. List all databases
./mongodb_migration.sh list

# 2. Test on one database
./mongodb_migration.sh test artha_cyopspath

# 3. Start full migration
./mongodb_migration.sh start

# 4. Monitor (separate terminal)
./migration_monitor.sh live

# 5. Start incremental sync (after migration)
./incremental_sync.sh continuous
```

---

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `mongodb_migration.sh` | Initial full database migration |
| `incremental_sync.sh` | Sync changes after migration |
| `new_db_sync.sh` | Migrate only new databases |
| `migration_monitor.sh` | Migration progress dashboard |
| `sync_monitor.sh` | Sync status dashboard |

---

## mongodb_migration.sh

Full database dump/restore with validation.

```bash
./mongodb_migration.sh <command>
```

| Command | Description |
|---------|-------------|
| `list` | Fetch all databases from Atlas |
| `test <db>` | Test migration on single database |
| `start` | Start/resume full migration |
| `status` | Show migration status |
| `retry` | Retry failed databases |
| `validate` | Re-validate all migrations |
| `reset` | Clear all status (start fresh) |

---

## incremental_sync.sh

Keep databases in sync with change streams.

```bash
./incremental_sync.sh <command>
```

| Command | Description |
|---------|-------------|
| `continuous` | Run continuous sync |
| `once` | Run single sync cycle |
| `lag` | Check pending changes |
| `status` | Show sync status |
| `set-time "YYYY-MM-DD HH:MM:SS"` | Set manual start time |
| `set-start-time` | Capture current Atlas time |
| `reset` | Clear resume token |

---

## new_db_sync.sh

Migrate only NEW databases not in original list.

```bash
./new_db_sync.sh <command>
```

| Command | Description |
|---------|-------------|
| `check` | Check for new databases |
| `migrate` | Migrate new databases |

---

## migration_monitor.sh

Real-time migration dashboard.

```bash
./migration_monitor.sh <command>
```

| Command | Description |
|---------|-------------|
| `live` | Real-time dashboard (default) |
| `summary` | One-time summary |
| `log` | Tail log file |

---

## sync_monitor.sh

Sync status dashboard.

```bash
./sync_monitor.sh
```

Shows: sync status, pending changes, synced operations.

---

## Systemd Service

```bash
# Install service
sudo cp mongodb_migration.service /etc/systemd/system/
sudo systemctl daemon-reload

# Control
sudo systemctl start mongodb_migration
sudo systemctl stop mongodb_migration
sudo systemctl status mongodb_migration
```

---

## File Locations

| File | Path |
|------|------|
| Database list | `/tmp/mongodb-migration/database_list.txt` |
| Migration log | `/tmp/mongodb-migration/migration.log` |
| Status files | `/tmp/mongodb-migration/status/` |
| Validation files | `/tmp/mongodb-migration/validation/` |
| Sync log | `/tmp/mongodb-migration/sync/incremental_sync.log` |
| Start timestamp | `/tmp/mongodb-migration/migration_start_timestamp.txt` |
