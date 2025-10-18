# Migration Guide: bakap → termiNAS

## Overview

This guide helps you migrate from an existing **bakap** installation to the new **termiNAS** naming.

> **⚠️ Important:** Since bakap is in alpha/experimental stage and this is a breaking change, we recommend a **clean installation** rather than in-place migration. However, we provide both options below.

## Option 1: Clean Installation (Recommended)

This is the safest and cleanest approach:

### Step 1: Backup Your Data

```bash
# Create a backup directory
sudo mkdir -p /backup/bakap-migration

# Backup all user data and snapshots
for user in $(ls /home | grep -v lost+found); do
    if [ -d "/home/$user/uploads" ]; then
        echo "Backing up $user..."
        sudo tar -czf "/backup/bakap-migration/$user-backup.tar.gz" \
            -C /home/$user uploads versions
    fi
done

# Backup configuration
sudo cp /etc/bakap-retention.conf /backup/bakap-migration/ 2>/dev/null || true
sudo cp /etc/systemd/system/bakap-monitor.service /backup/bakap-migration/ 2>/dev/null || true

echo "✓ Backup complete: /backup/bakap-migration/"
```

### Step 2: Uninstall bakap

```bash
# Stop and disable services
sudo systemctl stop bakap-monitor.service
sudo systemctl disable bakap-monitor.service

# Remove service files
sudo rm -f /etc/systemd/system/bakap-monitor.service
sudo systemctl daemon-reload

# Remove scripts
sudo rm -rf /var/backups/scripts/monitor_backups.sh
sudo rm -rf /var/backups/scripts/cleanup_snapshots.sh

# Remove configuration (keep backup!)
# sudo rm -f /etc/bakap-retention.conf  # Optional - already backed up

# Remove log rotation
sudo rm -f /etc/logrotate.d/bakap-monitor

# Remove inotify config
sudo rm -f /etc/sysctl.d/99-bakap-inotify.conf

# Remove fail2ban configs
sudo rm -f /etc/fail2ban/jail.d/bakap-*.conf
sudo rm -f /etc/fail2ban/filter.d/bakap-*.conf
sudo rm -f /etc/fail2ban/action.d/nftables-bakap.conf
sudo systemctl restart fail2ban

echo "✓ bakap uninstalled (user data preserved in /home)"
```

### Step 3: Install termiNAS

```bash
# Clone new repository
cd /opt
sudo git clone https://github.com/YiannisBourkelis/termiNAS.git
cd termiNAS

# Run setup
sudo ./src/server/setup.sh
```

### Step 4: Restore Users and Data

```bash
# For each backed up user, restore their data
cd /backup/bakap-migration

# Example for user "alice":
# 1. Create user in termiNAS
sudo /opt/termiNAS/src/server/create_user.sh alice

# 2. Restore their data
sudo tar -xzf alice-backup.tar.gz -C /home/alice/

# 3. Fix ownership if needed
sudo chown -R alice:backupusers /home/alice/uploads
sudo chown -R root:backupusers /home/alice/versions

# 4. Verify
ls -la /home/alice/
```

### Step 5: Restore Retention Configuration

```bash
# Copy your old retention settings to new config
sudo cp /backup/bakap-migration/bakap-retention.conf /etc/terminas-retention.conf

# Or manually edit:
sudo nano /etc/terminas-retention.conf
```

### Step 6: Restart Services

```bash
sudo systemctl restart terminas-monitor.service
sudo systemctl status terminas-monitor.service
```

## Option 2: In-Place Migration (Advanced)

> **⚠️ Warning:** This approach modifies your existing installation. Use at your own risk. Test in a VM first!

### Prerequisites

```bash
# Backup everything first!
sudo tar -czf /backup/bakap-full-backup-$(date +%Y%m%d).tar.gz \
    /home \
    /etc/bakap-retention.conf \
    /etc/systemd/system/bakap-monitor.service \
    /var/backups/scripts \
    /opt/bakap
```

### Migration Script

```bash
#!/usr/bin/env bash
# migrate-bakap-to-terminas.sh
# In-place migration from bakap to termiNAS

set -e

echo "=========================================="
echo "bakap → termiNAS Migration"
echo "=========================================="
echo ""
echo "⚠️  This will modify your existing installation"
echo "⚠️  Ensure you have backups before proceeding"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Step 1: Stopping services..."
sudo systemctl stop bakap-monitor.service

echo "Step 2: Renaming configuration files..."
sudo mv /etc/bakap-retention.conf /etc/terminas-retention.conf 2>/dev/null || true
sudo sed -i 's/bakap/terminas/g' /etc/terminas-retention.conf

echo "Step 3: Renaming systemd service..."
sudo mv /etc/systemd/system/bakap-monitor.service /etc/systemd/system/terminas-monitor.service
sudo sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /etc/systemd/system/terminas-monitor.service
sudo systemctl daemon-reload

echo "Step 4: Updating monitor scripts..."
if [ -f /var/backups/scripts/monitor_backups.sh ]; then
    sudo sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /var/backups/scripts/monitor_backups.sh
fi

if [ -f /var/backups/scripts/cleanup_snapshots.sh ]; then
    sudo sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /var/backups/scripts/cleanup_snapshots.sh
fi

echo "Step 5: Renaming runtime directories..."
sudo mkdir -p /var/run/terminas
if [ -d /var/run/bakap ]; then
    sudo mv /var/run/bakap/* /var/run/terminas/ 2>/dev/null || true
    sudo rmdir /var/run/bakap
fi

echo "Step 6: Renaming log rotation..."
if [ -f /etc/logrotate.d/bakap-monitor ]; then
    sudo mv /etc/logrotate.d/bakap-monitor /etc/logrotate.d/terminas-monitor
    sudo sed -i 's/bakap/terminas/g' /etc/logrotate.d/terminas-monitor
fi

echo "Step 7: Renaming log files..."
for log in /var/log/bakap*.log*; do
    if [ -f "$log" ]; then
        newlog=$(echo "$log" | sed 's/bakap/terminas/g')
        sudo mv "$log" "$newlog"
    fi
done

echo "Step 8: Updating inotify config..."
if [ -f /etc/sysctl.d/99-bakap-inotify.conf ]; then
    sudo mv /etc/sysctl.d/99-bakap-inotify.conf /etc/sysctl.d/99-terminas-inotify.conf
fi

echo "Step 9: Updating fail2ban configs..."
for f in /etc/fail2ban/jail.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        sudo mv "$f" "$newf"
        sudo sed -i 's/bakap/terminas/g; s/\[bakap-/\[terminas-/g' "$newf"
    fi
done

for f in /etc/fail2ban/filter.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        sudo mv "$f" "$newf"
        sudo sed -i 's/bakap/terminas/g' "$newf"
    fi
done

if [ -f /etc/fail2ban/action.d/nftables-bakap.conf ]; then
    sudo mv /etc/fail2ban/action.d/nftables-bakap.conf /etc/fail2ban/action.d/nftables-terminas.conf
    sudo sed -i 's/bakap/terminas/g' /etc/fail2ban/action.d/nftables-terminas.conf
fi

sudo systemctl restart fail2ban

echo "Step 10: Updating SSH config..."
sudo sed -i 's/# Bakap backup users/# termiNAS backup users/g' /etc/ssh/sshd_config
sudo systemctl reload sshd

echo "Step 11: Renaming installation directory..."
if [ -d /opt/bakap ]; then
    cd /opt
    sudo mv bakap termiNAS
    cd termiNAS
    sudo git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
fi

echo "Step 12: Starting services..."
sudo systemctl enable terminas-monitor.service
sudo systemctl start terminas-monitor.service

echo ""
echo "=========================================="
echo "✓ Migration Complete!"
echo "=========================================="
echo ""
echo "Verify installation:"
echo "  sudo systemctl status terminas-monitor.service"
echo "  tail -f /var/log/backup_monitor.log"
echo ""
echo "Check configuration:"
echo "  cat /etc/terminas-retention.conf"
echo ""
```

Save this as `/tmp/migrate-bakap-to-terminas.sh` and run:

```bash
chmod +x /tmp/migrate-bakap-to-terminas.sh
sudo /tmp/migrate-bakap-to-terminas.sh
```

## Client Migration

### Linux Clients

Update existing Linux client installations:

```bash
# Update paths
sudo mv /usr/local/bin/bakap-backup /usr/local/bin/terminas-backup
sudo mv /root/.bakap-credentials /root/.terminas-credentials

# Update scripts
for script in /usr/local/bin/terminas-backup/*.sh; do
    sudo sed -i 's/bakap/terminas/g' "$script"
done

# Update cron jobs
sudo crontab -l | sed 's|bakap-backup|terminas-backup|g; s|bakap-|terminas-|g' | sudo crontab -

# Update logrotate
for conf in /etc/logrotate.d/bakap-*; do
    if [ -f "$conf" ]; then
        newconf=$(echo "$conf" | sed 's/bakap-/terminas-/g')
        sudo mv "$conf" "$newconf"
        sudo sed -i 's/bakap/terminas/g' "$newconf"
    fi
done

# Rename log files
for log in /var/log/bakap-*.log*; do
    if [ -f "$log" ]; then
        newlog=$(echo "$log" | sed 's/bakap/terminas/g')
        sudo mv "$log" "$newlog"
    fi
done

echo "✓ Linux client migrated"
```

### Windows Clients

Update existing Windows client installations (run in PowerShell as Administrator):

```powershell
# Rename directories
Rename-Item "C:\Program Files\bakap-backup" "C:\Program Files\terminas-backup" -ErrorAction SilentlyContinue
Rename-Item "C:\ProgramData\bakap-credentials" "C:\ProgramData\terminas-credentials" -ErrorAction SilentlyContinue
Rename-Item "C:\ProgramData\bakap-logs" "C:\ProgramData\terminas-logs" -ErrorAction SilentlyContinue

# Update scheduled tasks
Get-ScheduledTask | Where-Object {$_.TaskName -like "Bakap-Backup-*"} | ForEach-Object {
    $oldName = $_.TaskName
    $newName = $oldName -replace "Bakap-Backup-", "termiNAS-Backup-"
    
    # Export task XML
    $xml = Export-ScheduledTask -TaskName $oldName
    
    # Update references in XML
    $xml = $xml -replace "bakap", "terminas"
    $xml = $xml -replace "Bakap", "termiNAS"
    
    # Re-register with new name
    Unregister-ScheduledTask -TaskName $oldName -Confirm:$false
    Register-ScheduledTask -TaskName $newName -Xml $xml | Out-Null
    
    Write-Host "✓ Renamed task: $oldName → $newName"
}

# Rename log files
Get-ChildItem "C:\ProgramData\terminas-logs\bakap-*.log" -ErrorAction SilentlyContinue | ForEach-Object {
    $newName = $_.Name -replace "bakap", "terminas"
    Rename-Item $_.FullName $newName
}

Write-Host "✓ Windows client migrated"
```

## Verification

After migration, verify everything works:

```bash
# Check service status
sudo systemctl status terminas-monitor.service

# Check logs
sudo tail -f /var/log/backup_monitor.log

# Check configuration
cat /etc/terminas-retention.conf

# Test client upload
# Linux:
/opt/termiNAS/src/client/linux/upload.sh -l /tmp/test.txt -u testuser -p "password" -s localhost

# List users
sudo /opt/termiNAS/src/server/manage_users.sh list
```

## Rollback

If something goes wrong, restore from backup:

```bash
# Restore full backup
sudo systemctl stop terminas-monitor.service
cd /
sudo tar -xzf /backup/bakap-full-backup-YYYYMMDD.tar.gz
sudo systemctl start bakap-monitor.service
```

## Support

If you encounter issues during migration:
- Check GitHub issues: https://github.com/YiannisBourkelis/termiNAS/issues
- Review logs: `/var/log/backup_monitor.log`
- Verify service: `sudo systemctl status terminas-monitor.service`

---

**Remember:** Since bakap is experimental/alpha, a clean installation is the recommended approach!
