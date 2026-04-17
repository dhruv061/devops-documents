# SFTP User Restriction (Chroot Jail Setup)

## Objective
Restrict user `icai-sftp` to only access:
`/home/icai-sftp/icai-sftp`

No access to any other directories on the server.

---

## 1. Directory Structure

```bash
sudo mkdir -p /home/icai-sftp/icai-sftp
```

### Set correct ownership and permissions

```bash
# Chroot base must be owned by root
sudo chown root:root /home/icai-sftp
sudo chmod 755 /home/icai-sftp

# Working directory owned by user
sudo chown icai-sftp:icai-sftp /home/icai-sftp/icai-sftp
```

---

## 2. SSH Configuration

Edit SSH config:

```bash
sudo nano /etc/ssh/sshd_config
```

Add at the bottom:

```bash
Match User icai-sftp
    ChrootDirectory /home/icai-sftp
    ForceCommand internal-sftp
```

---

## 3. Restart SSH Service

```bash
sudo systemctl restart ssh
```

---

## 4. Testing

```Note: SSH login not possible for this SFTP User ```

Connect via SFTP:

```bash
sftp icai-sftp@<server-ip>
```

Inside session:

```bash
pwd
ls
```

### Expected Result
- `pwd` → `/` (this is actually `/home/icai-sftp`)
- Only visible directory → `icai-sftp`

---

## 5. Troubleshooting

### Error: Broken pipe / Connection closed

Check permissions:

```bash
ls -ld /home/icai-sftp
ls -ld /home/icai-sftp/icai-sftp
```

Expected:

```bash
drwxr-xr-x root root /home/icai-sftp
drwxr-xr-x icai-sftp icai-sftp /home/icai-sftp/icai-sftp
```

---

### Check logs

```bash
sudo tail -f /var/log/auth.log
```

Common error:
`bad ownership or modes for chroot directory`

---

## 6. Key Rules (Do Not Break)

- Chroot directory must be owned by `root`
- User must NOT have write access to chroot root
- Always create a subdirectory for user operations
- Restart SSH after config changes

---

## Result

User `icai-sftp`:
- Can upload, download, delete files
- Is fully restricted to `/home/icai-sftp/icai-sftp`
- Cannot access any other part of the system
