# Server Migration Guide: bakap → termiNAS

## Overview

This guide will migrate an existing bakap installation to termiNAS on a remote server.

**Server Details:**
- Current installation path: `/opt/bakap`
- Service name: `bakap-monitor.service`
- Configuration: `/etc/bakap-retention.conf`

**Time required:** 15-20 minutes  
**Downtime:** ~5 minutes (while services restart)  
**Rollback:** Possible (backup created first)

---

## ⚠️ Before You Start

### Prerequisites

1. **SSH access to the remote server with sudo privileges**
2. **Backup server is running and accessible**
3. **No active uploads in progress** (check with `lsof +D /home/*/uploads`)

### Important Notes

- ✅ User data in `/home/*/uploads` and `/home/*/versions` is NOT affected
- ✅ Snapshots remain intact and accessible
- ✅ Users can continue accessing via SFTP (no user-facing changes)
- ⚠️ Services will restart (brief interruption to monitoring)

---

## Step-by-Step Migration

### Step 0: Connect to Your Remote Server

```bash
# SSH into your backup server
ssh user@your-backup-server

# Switch to root or use sudo for all commands
sudo su -
# OR: prefix all commands with 'sudo'
```

---

### Step 1: Create Full Backup

```bash
# Create backup directory
mkdir -p /backup/bakap-to-terminas-$(date +%Y%m%d)
cd /backup/bakap-to-terminas-$(date +%Y%m%d)

# Backup configuration files
cp /etc/bakap-retention.conf . 2>/dev/null || echo "No retention config found"
cp /etc/systemd/system/bakap-monitor.service . 2>/dev/null || true
cp -r /etc/fail2ban/jail.d/bakap-*.conf . 2>/dev/null || true
cp -r /etc/fail2ban/filter.d/bakap-*.conf . 2>/dev/null || true
cp -r /etc/fail2ban/action.d/nftables-bakap.conf . 2>/dev/null || true
cp /etc/logrotate.d/bakap-monitor . 2>/dev/null || true
cp /etc/sysctl.d/99-bakap-inotify.conf . 2>/dev/null || true

# Backup scripts
cp -r /var/backups/scripts /backup/bakap-to-terminas-$(date +%Y%m%d)/

# Backup /opt/bakap git state
cd /opt/bakap
git status > /backup/bakap-to-terminas-$(date +%Y%m%d)/git-status.txt
git remote -v > /backup/bakap-to-terminas-$(date +%Y%m%d)/git-remote.txt

echo "✓ Backup created in /backup/bakap-to-terminas-$(date +%Y%m%d)"
```

---

### Step 2: Stop bakap Services

```bash
# Stop the monitoring service
systemctl stop bakap-monitor.service

# Verify it stopped
systemctl status bakap-monitor.service

# Expected: "Active: inactive (dead)"
```

---

### Step 3: Update Git Repository

```bash
cd /opt/bakap

# Update remote URL to new repository name
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git

# Verify
git remote -v
# Expected output:
# origin  https://github.com/YiannisBourkelis/termiNAS.git (fetch)
# origin  https://github.com/YiannisBourkelis/termiNAS.git (push)

# Pull latest changes (includes renamed files)
git fetch origin
git pull origin main

# Check current branch and status
git status
```

---

### Step 4: Rename Configuration Files

```bash
# Rename retention configuration
if [ -f /etc/bakap-retention.conf ]; then
    mv /etc/bakap-retention.conf /etc/terminas-retention.conf
    echo "✓ Renamed /etc/bakap-retention.conf → /etc/terminas-retention.conf"
fi

# Update content references
sed -i 's/bakap/terminas/g' /etc/terminas-retention.conf
sed -i 's/BAKAP/TERMINAS/g' /etc/terminas-retention.conf

# Verify
cat /etc/terminas-retention.conf | head -5
```

---

### Step 5: Rename systemd Service

```bash
# Rename service file
mv /etc/systemd/system/bakap-monitor.service /etc/systemd/system/terminas-monitor.service

# Update references inside the service file
sed -i 's/bakap/terminas/g' /etc/systemd/system/terminas-monitor.service
sed -i 's/BAKAP/TERMINAS/g' /etc/systemd/system/terminas-monitor.service
sed -i 's/Bakap/termiNAS/g' /etc/systemd/system/terminas-monitor.service

# Reload systemd to recognize the new service name
systemctl daemon-reload

# Verify the service file
systemctl cat terminas-monitor.service | head -10
```

---

### Step 6: Update Monitor Scripts

```bash
# Update monitor_backups.sh
sed -i 's/bakap/terminas/g' /var/backups/scripts/monitor_backups.sh
sed -i 's/BAKAP/TERMINAS/g' /var/backups/scripts/monitor_backups.sh
sed -i 's/Bakap/termiNAS/g' /var/backups/scripts/monitor_backups.sh

# Update cleanup_snapshots.sh
sed -i 's/bakap/terminas/g' /var/backups/scripts/cleanup_snapshots.sh
sed -i 's/BAKAP/TERMINAS/g' /var/backups/scripts/cleanup_snapshots.sh
sed -i 's/Bakap/termiNAS/g' /var/backups/scripts/cleanup_snapshots.sh

# Verify
head -20 /var/backups/scripts/monitor_backups.sh | grep -i terminas
```

---

### Step 7: Rename Runtime Directories

```bash
# Create new runtime directory
mkdir -p /var/run/terminas

# Move runtime state files if they exist
if [ -d /var/run/bakap ]; then
    mv /var/run/bakap/* /var/run/terminas/ 2>/dev/null || true
    rmdir /var/run/bakap
    echo "✓ Moved runtime files to /var/run/terminas"
fi

# Set permissions
chmod 755 /var/run/terminas
```

---

### Step 8: Update Log Configuration

```bash
# Rename logrotate configuration
if [ -f /etc/logrotate.d/bakap-monitor ]; then
    mv /etc/logrotate.d/bakap-monitor /etc/logrotate.d/terminas-monitor
    sed -i 's/bakap/terminas/g' /etc/logrotate.d/terminas-monitor
    echo "✓ Renamed logrotate config"
fi

# Rename existing log files (optional - logs will rotate naturally)
# Uncomment if you want to rename immediately:
# for log in /var/log/bakap*.log*; do
#     if [ -f "$log" ]; then
#         newlog=$(echo "$log" | sed 's/bakap/terminas/g')
#         mv "$log" "$newlog"
#         echo "Renamed: $log → $newlog"
#     fi
# done
```

---

### Step 9: Update inotify Configuration

```bash
# Rename inotify sysctl config
if [ -f /etc/sysctl.d/99-bakap-inotify.conf ]; then
    mv /etc/sysctl.d/99-bakap-inotify.conf /etc/sysctl.d/99-terminas-inotify.conf
    echo "✓ Renamed inotify config"
fi
```

---

### Step 10: Update fail2ban Configuration

```bash
# Rename jail configurations
for f in /etc/fail2ban/jail.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        mv "$f" "$newf"
        
        # Update content
        sed -i 's/bakap/terminas/g' "$newf"
        sed -i 's/\[bakap-/\[terminas-/g' "$newf"
        sed -i 's/Bakap/termiNAS/g' "$newf"
        
        echo "✓ Renamed: $f → $newf"
    fi
done

# Rename filter configurations
for f in /etc/fail2ban/filter.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        mv "$f" "$newf"
        
        # Update content
        sed -i 's/bakap/terminas/g' "$newf"
        sed -i 's/Bakap/termiNAS/g' "$newf"
        
        echo "✓ Renamed: $f → $newf"
    fi
done

# Rename action configuration
if [ -f /etc/fail2ban/action.d/nftables-bakap.conf ]; then
    mv /etc/fail2ban/action.d/nftables-bakap.conf /etc/fail2ban/action.d/nftables-terminas.conf
    sed -i 's/bakap/terminas/g' /etc/fail2ban/action.d/nftables-terminas.conf
    echo "✓ Renamed nftables action"
fi

# Restart fail2ban to apply changes
systemctl restart fail2ban

# Verify fail2ban is running
systemctl status fail2ban | head -5
```

---

### Step 11: Update SSH Configuration Comments

```bash
# Update SSH config comments (cosmetic)
sed -i 's/# Bakap backup users/# termiNAS backup users/g' /etc/ssh/sshd_config

# Verify (no restart needed - just a comment)
grep termiNAS /etc/ssh/sshd_config
```

---

### Step 12: Update Samba Configuration (if enabled)

```bash
# Check if Samba is configured
if grep -q "Bakap" /etc/samba/smb.conf 2>/dev/null; then
    # Update Samba configuration
    sed -i 's/Bakap Backup Server/termiNAS Backup Server/g' /etc/samba/smb.conf
    sed -i 's/Bakap backup/termiNAS backup/g' /etc/samba/smb.conf
    
    # Restart Samba
    systemctl restart smbd nmbd 2>/dev/null || true
    
    echo "✓ Updated Samba configuration"
else
    echo "ℹ Samba not configured or not installed"
fi
```

---

### Step 13: Rename Installation Directory

```bash
# Rename /opt/bakap to /opt/terminas
cd /opt
mv bakap terminas

# Verify
ls -ld /opt/terminas
cd /opt/terminas
git status
```

---

### Step 14: Start termiNAS Services

```bash
# Enable the new service name
systemctl enable terminas-monitor.service

# Start the service
systemctl start terminas-monitor.service

# Check status
systemctl status terminas-monitor.service

# Expected: "Active: active (running)"
```

---

### Step 15: Verify Migration

```bash
# Check service is running
systemctl status terminas-monitor.service

# Check logs for activity
tail -f /var/log/backup_monitor.log

# Press Ctrl+C to exit log viewing

# Verify configuration
cat /etc/terminas-retention.conf

# Check fail2ban jails
fail2ban-client status | grep terminas

# Test file upload (create a test file)
echo "Migration test - $(date)" > /tmp/test-migration.txt
su - testuser -c "echo 'test'" 2>/dev/null || echo "Create a test user if needed"

# Check user list
/opt/terminas/src/server/manage_users.sh list
```

---

## ✅ Verification Checklist

After migration, verify these items:

### Services
- [ ] `systemctl status terminas-monitor.service` shows "active (running)"
- [ ] `systemctl status fail2ban` shows "active (running)"
- [ ] No errors in `/var/log/backup_monitor.log`

### Configuration Files
- [ ] `/etc/terminas-retention.conf` exists and contains correct settings
- [ ] `/etc/systemd/system/terminas-monitor.service` exists
- [ ] fail2ban jails show `terminas-*` instead of `bakap-*`

### Directory Structure
- [ ] `/opt/terminas` exists (old `/opt/bakap` renamed)
- [ ] `/var/run/terminas` exists and contains runtime state files
- [ ] Git remote points to `termiNAS` repository

### User Data (Should be Unchanged)
- [ ] All user home directories intact: `/home/*/`
- [ ] Uploads directory accessible: `/home/*/uploads/`
- [ ] Snapshots intact: `/home/*/versions/*/`
- [ ] Users can connect via SFTP

### Test Upload
- [ ] Create test file: `touch /tmp/test.txt`
- [ ] Upload via SFTP to a test user
- [ ] Verify snapshot is created in `/home/testuser/versions/`

---

## 🔄 Rollback Procedure (If Needed)

If something goes wrong, you can rollback:

```bash
# Stop new service
systemctl stop terminas-monitor.service
systemctl disable terminas-monitor.service

# Restore from backup
BACKUP_DIR="/backup/bakap-to-terminas-$(date +%Y%m%d)"

# Restore configuration files
cp $BACKUP_DIR/bakap-retention.conf /etc/bakap-retention.conf
cp $BACKUP_DIR/bakap-monitor.service /etc/systemd/system/
cp $BACKUP_DIR/bakap-*.conf /etc/fail2ban/jail.d/ 2>/dev/null || true
cp $BACKUP_DIR/bakap-*.conf /etc/fail2ban/filter.d/ 2>/dev/null || true

# Restore scripts
cp -r $BACKUP_DIR/scripts/* /var/backups/scripts/

# Rename directory back
cd /opt
mv terminas bakap

# Restore git remote
cd /opt/bakap
git remote set-url origin https://github.com/YiannisBourkelis/bakap.git

# Reload and restart old service
systemctl daemon-reload
systemctl enable bakap-monitor.service
systemctl start bakap-monitor.service

echo "Rollback complete. Check: systemctl status bakap-monitor.service"
```

---

## 📝 Post-Migration Tasks

### Update Client Configurations (Later)

Your existing clients will continue to work (they connect via SFTP to the same server), but you may want to update their local configurations:

**Linux Clients:**
```bash
# Update client scripts if installed in /opt/bakap
sudo mv /usr/local/bin/bakap-backup /usr/local/bin/terminas-backup
sudo mv /root/.bakap-credentials /root/.terminas-credentials
# Update cron jobs to reference new paths
```

**Windows Clients:**
```powershell
# Update client scripts if installed
Rename-Item "C:\Program Files\bakap-backup" "terminas-backup"
Rename-Item "C:\ProgramData\bakap-credentials" "terminas-credentials"
# Update scheduled tasks to reference new paths
```

---

## 🎉 Migration Complete!

Your server has been successfully migrated from bakap to termiNAS!

### Summary of Changes

**Renamed:**
- ✅ `/opt/bakap` → `/opt/terminas`
- ✅ `bakap-monitor.service` → `terminas-monitor.service`
- ✅ `/etc/bakap-retention.conf` → `/etc/terminas-retention.conf`
- ✅ All fail2ban configurations
- ✅ Runtime directories and log files
- ✅ Git remote URL

**Preserved:**
- ✅ All user data in `/home/*/uploads` and `/home/*/versions`
- ✅ All Btrfs snapshots
- ✅ User accounts and SSH access
- ✅ fail2ban ban history and rules
- ✅ Retention policies

**No User Impact:**
- ✅ Users can still connect via SFTP with same credentials
- ✅ Uploads and snapshots work exactly as before
- ✅ No data loss or corruption

---

## 📞 Need Help?

If you encounter any issues:

1. **Check service status:** `systemctl status terminas-monitor.service`
2. **Check logs:** `tail -100 /var/log/backup_monitor.log`
3. **Verify fail2ban:** `fail2ban-client status`
4. **Test SFTP connection:** Try uploading a test file
5. **Rollback if needed:** Use the rollback procedure above

---

**Congratulations! Your bakap server is now termiNAS!** 🎊
