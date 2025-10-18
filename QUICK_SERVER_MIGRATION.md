# Quick Reference: Remote Server Migration

## 🚀 Fast Track - Automated Migration

**For most users - use the automated script:**

```bash
# 1. SSH to your server
ssh user@your-backup-server

# 2. Download the migration script
cd /tmp
wget https://raw.githubusercontent.com/YiannisBourkelis/termiNAS/main/migrate-server.sh
# OR: Copy the script from your local machine
scp /Users/yiannis/Projects/termiNAS/migrate-server.sh user@your-server:/tmp/

# 3. Make it executable
chmod +x /tmp/migrate-server.sh

# 4. Run the migration (as root)
sudo /tmp/migrate-server.sh

# 5. Verify everything works
sudo systemctl status terminas-monitor.service
tail -50 /var/log/backup_monitor.log
```

**That's it! The script handles all 15 steps automatically.** ✅

---

## 📋 Manual Migration - Essential Commands

**If you prefer to run commands manually or need to customize:**

```bash
# SSH to your server
ssh user@your-backup-server
sudo su -

# === BACKUP (CRITICAL!) ===
BACKUP_DIR="/backup/bakap-to-terminas-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cp /etc/bakap-retention.conf "$BACKUP_DIR/"
cp /etc/systemd/system/bakap-monitor.service "$BACKUP_DIR/"
cp -r /var/backups/scripts "$BACKUP_DIR/"

# === STOP SERVICES ===
systemctl stop bakap-monitor.service

# === UPDATE GIT ===
cd /opt/bakap
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
git pull origin main

# === RENAME CONFIGS ===
mv /etc/bakap-retention.conf /etc/terminas-retention.conf
sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /etc/terminas-retention.conf

# === RENAME SERVICE ===
mv /etc/systemd/system/bakap-monitor.service /etc/systemd/system/terminas-monitor.service
sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g; s/Bakap/termiNAS/g' /etc/systemd/system/terminas-monitor.service
systemctl daemon-reload

# === UPDATE SCRIPTS ===
sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /var/backups/scripts/monitor_backups.sh
sed -i 's/bakap/terminas/g; s/BAKAP/TERMINAS/g' /var/backups/scripts/cleanup_snapshots.sh

# === RENAME DIRECTORIES ===
mkdir -p /var/run/terminas
mv /var/run/bakap/* /var/run/terminas/ 2>/dev/null || true
rmdir /var/run/bakap 2>/dev/null || true

# === UPDATE FAIL2BAN ===
cd /etc/fail2ban/jail.d && for f in bakap-*.conf; do mv "$f" "${f/bakap-/terminas-}"; sed -i 's/bakap/terminas/g' "${f/bakap-/terminas-}"; done
cd /etc/fail2ban/filter.d && for f in bakap-*.conf; do mv "$f" "${f/bakap-/terminas-}"; sed -i 's/bakap/terminas/g' "${f/bakap-/terminas-}"; done
systemctl restart fail2ban

# === RENAME INSTALLATION ===
cd /opt && mv bakap terminas

# === START SERVICES ===
systemctl enable terminas-monitor.service
systemctl start terminas-monitor.service

# === VERIFY ===
systemctl status terminas-monitor.service
tail -50 /var/log/backup_monitor.log
```

---

## ✅ Post-Migration Checklist

```bash
# 1. Check service status
systemctl status terminas-monitor.service
# Should show: Active: active (running)

# 2. Check logs
tail -50 /var/log/backup_monitor.log
# Should show recent activity with "termiNAS" references

# 3. List users (verify script path works)
/opt/terminas/src/server/manage_users.sh list

# 4. Check fail2ban
fail2ban-client status | grep terminas
# Should show: terminas-sshd, terminas-samba (if configured)

# 5. Verify git
cd /opt/terminas && git remote -v
# Should show: https://github.com/YiannisBourkelis/termiNAS.git

# 6. Test SFTP connection
sftp testuser@localhost
# Should connect successfully

# 7. Check configuration
cat /etc/terminas-retention.conf
# Should exist and show terminas references
```

---

## 🔄 Rollback (If Needed)

```bash
# Stop new services
systemctl stop terminas-monitor.service

# Restore from backup
BACKUP_DIR="/backup/bakap-to-terminas-YYYYMMDD"  # Use actual date
cp "$BACKUP_DIR/bakap-retention.conf" /etc/
cp "$BACKUP_DIR/bakap-monitor.service" /etc/systemd/system/
cp -r "$BACKUP_DIR/scripts/"* /var/backups/scripts/

# Rename back
cd /opt && mv terminas bakap
cd /opt/bakap
git remote set-url origin https://github.com/YiannisBourkelis/bakap.git

# Restart old service
systemctl daemon-reload
systemctl start bakap-monitor.service
```

---

## 📞 Troubleshooting

### Service won't start
```bash
# Check service status
systemctl status terminas-monitor.service

# Check logs
journalctl -u terminas-monitor.service -n 50

# Verify script exists and is executable
ls -l /var/backups/scripts/monitor_backups.sh
```

### fail2ban errors
```bash
# Check fail2ban status
fail2ban-client status

# Test jail configuration
fail2ban-client -t

# Check logs
tail -100 /var/log/fail2ban.log
```

### Git issues
```bash
cd /opt/terminas
git remote -v
git status
git pull origin main
```

---

## 📚 Full Documentation

For detailed step-by-step instructions with explanations:
- **SERVER_MIGRATION_GUIDE.md** - Complete migration guide
- **MIGRATION.md** - General migration documentation

---

## ⏱️ Migration Time Estimate

- **Automated script**: ~5 minutes
- **Manual steps**: ~15-20 minutes
- **Downtime**: ~5 minutes (services restart)

---

## 🎉 Success!

After migration, your server will be running termiNAS with:
- ✅ All user data preserved
- ✅ All snapshots intact
- ✅ Services running with new names
- ✅ Git repository updated
- ✅ Configuration files renamed

**Users will see NO difference** - they can continue connecting via SFTP with the same credentials!
