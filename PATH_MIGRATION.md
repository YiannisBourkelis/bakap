# termiNAS Path Migration Summary

## Overview
This document describes the path standardization changes made to termiNAS to use consistent, branded naming throughout the project.

## Path Changes

### Scripts Directory
- **Old:** `/var/backups/scripts/`
- **New:** `/var/terminas/scripts/`
- **Reason:** Use termiNAS-specific directory instead of generic "backups" name

### Monitor Script
- **Old:** `/var/backups/scripts/monitor_backups.sh`
- **New:** `/var/terminas/scripts/terminas-monitor.sh`
- **Reason:** Consistent with service name (`terminas-monitor.service`)

### Cleanup Script
- **Old:** `/var/backups/scripts/cleanup_snapshots.sh`
- **New:** `/var/terminas/scripts/terminas-cleanup.sh`
- **Reason:** Match termiNAS branding and naming convention

### Log File
- **Old:** `/var/log/backup_monitor.log`
- **New:** `/var/log/terminas.log`
- **Reason:** Simpler, branded name (not "backup_monitor")

### Logrotate Configuration
- **Old:** `/etc/logrotate.d/terminas-monitor`
- **New:** `/etc/logrotate.d/terminas`
- **Reason:** Match simplified log file name

## Unchanged Paths
These paths already used termiNAS naming:
- `/etc/terminas-retention.conf` ✓
- `/etc/systemd/system/terminas-monitor.service` ✓
- `/var/run/terminas/` ✓
- `/opt/terminas/` ✓
- User data: `/home/*/uploads/`, `/home/*/versions/` ✓

## Migration Paths

### New Installations
Run `setup.sh` normally. It will create the new path structure automatically.

### Existing Installations

You have **two options** depending on your situation:

#### Option 1: Path-Only Migration (Recommended for most users)
If you're already running termiNAS (not bakap), use `migrate-paths.sh`:

```bash
cd /opt/terminas
sudo ./migrate-paths.sh
```

This script will:
1. Stop the monitor service
2. Create `/var/terminas/scripts/` directory
3. Copy and rename scripts to new locations
4. Migrate log file to `/var/log/terminas.log`
5. Update systemd service to use new paths
6. Update logrotate configuration
7. Update crontab for cleanup script
8. Restart services
9. Verify migration success

**Backup:** Creates backup in `/backup/path-migration-YYYYMMDD_HHMMSS/`

#### Option 2: Full Migration (For bakap→termiNAS rename)
If you're still running bakap and need to migrate to termiNAS AND update paths:

```bash
cd /opt/bakap  # Still bakap at this point
sudo ./migrate-server.sh
```

This script handles:
1. All bakap→termiNAS rename operations
2. Git repository update
3. Path migration (includes all changes from migrate-paths.sh)
4. Configuration file updates
5. fail2ban updates
6. Samba updates (if configured)

**Backup:** Creates backup in `/backup/bakap-to-terminas-YYYYMMDD-HHMMSS/`

## Impact on Users

### No User Action Required
- SFTP connections continue to work (same credentials, same paths)
- User data is unchanged (`/home/*/uploads/`, `/home/*/versions/`)
- Automatic backups continue without interruption
- Snapshots are still created in real-time

### What Changes
- Server logs are now in `/var/log/terminas.log` instead of `backup_monitor.log`
- Monitor with: `tail -f /var/log/terminas.log`
- Scripts are in `/var/terminas/scripts/` instead of `/var/backups/scripts/`

## Verification After Migration

Check that everything is working:

```bash
# Service status
systemctl status terminas-monitor.service

# Should show: ExecStart=/bin/bash /var/terminas/scripts/terminas-monitor.sh

# Log file exists and is being written
ls -lh /var/log/terminas.log
tail -20 /var/log/terminas.log

# Scripts exist
ls -lh /var/terminas/scripts/
# Should show: terminas-monitor.sh, terminas-cleanup.sh

# Crontab updated
crontab -l | grep terminas-cleanup.sh
# Should show: 0 3 * * * /var/terminas/scripts/terminas-cleanup.sh

# Test backup - upload a file via SFTP and check log
tail -f /var/log/terminas.log
```

## Rollback (if needed)

### If using migrate-paths.sh
The backup directory contains all original files:

```bash
# Stop service
sudo systemctl stop terminas-monitor.service

# Restore from backup (use your actual backup directory name)
BACKUP_DIR="/backup/path-migration-20251018_123456"

# Restore scripts
sudo cp -a "$BACKUP_DIR/scripts-old/"* /var/backups/scripts/

# Restore service file
sudo cp "$BACKUP_DIR/terminas-monitor.service.old" \
    /etc/systemd/system/terminas-monitor.service

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl start terminas-monitor.service
```

### If using migrate-server.sh
Full instructions in `SERVER_MIGRATION_GUIDE.md` rollback section.

## Files Updated

### Source Code
- `src/server/setup.sh` - Creates new directory structure and scripts
- `src/server/create_user.sh` - No changes needed
- `src/server/delete_user.sh` - No changes needed  
- `src/server/manage_users.sh` - No changes needed

### Migration Scripts
- `migrate-paths.sh` - **NEW** - Standalone path migration
- `migrate-server.sh` - Updated to handle path migration during bakap→termiNAS rename

### Documentation
- `PATH_MIGRATION.md` - This file
- `SERVER_MIGRATION_GUIDE.md` - Updated with new paths (if applicable)
- `README.md` - Updated installation instructions (if applicable)

## Timeline

- **Before:** Generic "backup" naming
- **After:** Consistent "termiNAS" branding throughout

## Questions?

- **Do I need to migrate?** Only if upgrading from an older version
- **Will my backups stop working?** No - migration is backward compatible
- **Can I keep old paths?** Yes, but not recommended (inconsistent branding)
- **When should I migrate?** At your convenience - no security urgency

## Support

If you encounter issues:
1. Check service status: `systemctl status terminas-monitor.service`
2. Check logs: `journalctl -u terminas-monitor.service -n 50`
3. Review backup directory for rollback option
4. File an issue: https://github.com/YiannisBourkelis/termiNAS/issues

---

*Document created: October 18, 2025*  
*termiNAS version: Development (path standardization update)*
