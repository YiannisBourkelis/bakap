#!/bin/bash
# migrate-paths.sh - Migrate termiNAS paths to new naming convention
# This script updates existing termiNAS installations to use the new
# termiNAS-branded paths introduced in the latest version.
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/termiNAS
#
# Old paths → New paths:
#   /var/backups/scripts/ → /var/terminas/scripts/
#   monitor_backups.sh → terminas-monitor.sh
#   cleanup_snapshots.sh → terminas-cleanup.sh
#   /var/log/backup_monitor.log → /var/log/terminas.log
#   /etc/logrotate.d/terminas-monitor → /etc/logrotate.d/terminas
#
# Usage: sudo ./migrate-paths.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}termiNAS Path Migration Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Confirmation prompt
echo -e "${YELLOW}This script will update your termiNAS installation to use new paths:${NC}"
echo ""
echo "  Script directory:"
echo "    /var/backups/scripts/ → /var/terminas/scripts/"
echo ""
echo "  Script names:"
echo "    monitor_backups.sh → terminas-monitor.sh"
echo "    cleanup_snapshots.sh → terminas-cleanup.sh"
echo ""
echo "  Log file:"
echo "    /var/log/backup_monitor.log → /var/log/terminas.log"
echo ""
echo "  Logrotate config:"
echo "    /etc/logrotate.d/terminas-monitor → /etc/logrotate.d/terminas"
echo ""
echo -e "${YELLOW}The old files will be backed up before migration.${NC}"
echo ""
read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi
echo ""

# Step counter
STEP=0

step() {
    STEP=$((STEP + 1))
    echo -e "${BLUE}[$STEP] $1${NC}"
}

# Check if old paths exist
if [ ! -d "/var/backups/scripts" ] && [ ! -f "/var/log/backup_monitor.log" ]; then
    echo -e "${YELLOW}No old paths found. Your installation may already be migrated.${NC}"
    echo ""
    echo "If you're doing a fresh install, run setup.sh instead."
    exit 0
fi

# Create backup directory
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/path-migration-$BACKUP_DATE"
step "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓ Backup directory created${NC}"
echo ""

# Stop the monitor service
step "Stopping terminas-monitor service"
if systemctl is-active --quiet terminas-monitor.service; then
    systemctl stop terminas-monitor.service
    echo -e "${GREEN}✓ Service stopped${NC}"
else
    echo -e "${YELLOW}Service not running${NC}"
fi
echo ""

# Migrate /var/backups/scripts to /var/terminas/scripts
if [ -d "/var/backups/scripts" ]; then
    step "Migrating script directory"
    
    # Backup old directory
    cp -a /var/backups/scripts "$BACKUP_DIR/scripts-old"
    echo "  - Backed up to $BACKUP_DIR/scripts-old"
    
    # Create new directory
    mkdir -p /var/terminas/scripts
    
    # Copy and rename scripts
    if [ -f "/var/backups/scripts/monitor_backups.sh" ]; then
        cp /var/backups/scripts/monitor_backups.sh /var/terminas/scripts/terminas-monitor.sh
        chmod +x /var/terminas/scripts/terminas-monitor.sh
        echo "  - Migrated: monitor_backups.sh → terminas-monitor.sh"
    fi
    
    if [ -f "/var/backups/scripts/cleanup_snapshots.sh" ]; then
        cp /var/backups/scripts/cleanup_snapshots.sh /var/terminas/scripts/terminas-cleanup.sh
        chmod +x /var/terminas/scripts/terminas-cleanup.sh
        echo "  - Migrated: cleanup_snapshots.sh → terminas-cleanup.sh"
    fi
    
    # Copy any other files
    for file in /var/backups/scripts/*; do
        if [ -f "$file" ]; then
            basename=$(basename "$file")
            if [ "$basename" != "monitor_backups.sh" ] && [ "$basename" != "cleanup_snapshots.sh" ]; then
                cp "$file" "/var/terminas/scripts/$basename"
                echo "  - Copied: $basename"
            fi
        fi
    done
    
    echo -e "${GREEN}✓ Scripts migrated${NC}"
else
    echo -e "${YELLOW}No /var/backups/scripts directory found${NC}"
fi
echo ""

# Migrate log file
if [ -f "/var/log/backup_monitor.log" ]; then
    step "Migrating log file"
    
    # Backup old log
    cp /var/log/backup_monitor.log "$BACKUP_DIR/backup_monitor.log"
    echo "  - Backed up to $BACKUP_DIR/backup_monitor.log"
    
    # Copy to new location (keep old one for now)
    cp /var/log/backup_monitor.log /var/log/terminas.log
    chown root:adm /var/log/terminas.log 2>/dev/null || true
    chmod 640 /var/log/terminas.log 2>/dev/null || true
    
    echo "  - Migrated: backup_monitor.log → terminas.log"
    echo -e "${GREEN}✓ Log file migrated${NC}"
else
    echo -e "${YELLOW}No /var/log/backup_monitor.log found${NC}"
fi
echo ""

# Update systemd service to use new paths
step "Updating systemd service"
if [ -f "/etc/systemd/system/terminas-monitor.service" ]; then
    # Backup service file
    cp /etc/systemd/system/terminas-monitor.service "$BACKUP_DIR/terminas-monitor.service.old"
    
    # Update ExecStart path
    sed -i 's|/var/backups/scripts/monitor_backups.sh|/var/terminas/scripts/terminas-monitor.sh|g' \
        /etc/systemd/system/terminas-monitor.service
    
    echo "  - Updated service to use /var/terminas/scripts/terminas-monitor.sh"
    echo -e "${GREEN}✓ Service updated${NC}"
else
    echo -e "${YELLOW}No service file found at /etc/systemd/system/terminas-monitor.service${NC}"
fi
echo ""

# Update logrotate configuration
step "Updating logrotate configuration"
if [ -f "/etc/logrotate.d/terminas-monitor" ]; then
    # Backup old config
    cp /etc/logrotate.d/terminas-monitor "$BACKUP_DIR/logrotate-terminas-monitor.old"
    
    # Create new config
    cat > /etc/logrotate.d/terminas <<'LR'
/var/log/terminas.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 640 root adm
}
LR
    
    echo "  - Created /etc/logrotate.d/terminas"
    echo "  - Old config backed up (can be removed manually)"
    echo -e "${GREEN}✓ Logrotate updated${NC}"
else
    echo -e "${YELLOW}No /etc/logrotate.d/terminas-monitor found${NC}"
fi
echo ""

# Update crontab for cleanup script
step "Updating crontab"
CRON_UPDATED=false
if crontab -l 2>/dev/null | grep -q "cleanup_snapshots.sh"; then
    # Get current crontab, update the path, and reinstall
    crontab -l 2>/dev/null | \
        sed 's|/var/backups/scripts/cleanup_snapshots.sh|/var/terminas/scripts/terminas-cleanup.sh|g' | \
        crontab -
    CRON_UPDATED=true
    echo "  - Updated crontab to use /var/terminas/scripts/terminas-cleanup.sh"
    echo -e "${GREEN}✓ Crontab updated${NC}"
else
    echo -e "${YELLOW}No cleanup_snapshots.sh entry found in crontab${NC}"
fi
echo ""

# Reload systemd and restart service
step "Reloading systemd and restarting service"
systemctl daemon-reload
echo "  - Systemd daemon reloaded"

if systemctl start terminas-monitor.service; then
    echo "  - Service started successfully"
    echo -e "${GREEN}✓ Service running${NC}"
else
    echo -e "${RED}✗ Failed to start service${NC}"
    echo "  Check logs: journalctl -u terminas-monitor.service -n 50"
fi
echo ""

# Verification
step "Verifying migration"
ERRORS=0

# Check new script directory
if [ -d "/var/terminas/scripts" ]; then
    echo -e "  ${GREEN}✓${NC} /var/terminas/scripts/ exists"
else
    echo -e "  ${RED}✗${NC} /var/terminas/scripts/ NOT found"
    ERRORS=$((ERRORS + 1))
fi

# Check new scripts
if [ -f "/var/terminas/scripts/terminas-monitor.sh" ]; then
    echo -e "  ${GREEN}✓${NC} terminas-monitor.sh exists"
else
    echo -e "  ${RED}✗${NC} terminas-monitor.sh NOT found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "/var/terminas/scripts/terminas-cleanup.sh" ]; then
    echo -e "  ${GREEN}✓${NC} terminas-cleanup.sh exists"
else
    echo -e "  ${RED}✗${NC} terminas-cleanup.sh NOT found"
    ERRORS=$((ERRORS + 1))
fi

# Check new log file
if [ -f "/var/log/terminas.log" ]; then
    echo -e "  ${GREEN}✓${NC} /var/log/terminas.log exists"
else
    echo -e "  ${RED}✗${NC} /var/log/terminas.log NOT found"
    ERRORS=$((ERRORS + 1))
fi

# Check service status
if systemctl is-active --quiet terminas-monitor.service; then
    echo -e "  ${GREEN}✓${NC} terminas-monitor.service is active"
else
    echo -e "  ${RED}✗${NC} terminas-monitor.service is NOT active"
    ERRORS=$((ERRORS + 1))
fi

# Check service uses new path
if grep -q "/var/terminas/scripts/terminas-monitor.sh" /etc/systemd/system/terminas-monitor.service 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Service uses new script path"
else
    echo -e "  ${RED}✗${NC} Service does NOT use new script path"
    ERRORS=$((ERRORS + 1))
fi

# Check crontab
if [ "$CRON_UPDATED" = true ]; then
    if crontab -l 2>/dev/null | grep -q "terminas-cleanup.sh"; then
        echo -e "  ${GREEN}✓${NC} Crontab uses new script path"
    else
        echo -e "  ${RED}✗${NC} Crontab does NOT use new script path"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# Final summary
echo -e "${BLUE}========================================${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Migration completed successfully!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "New paths:"
    echo "  - Scripts: /var/terminas/scripts/"
    echo "  - Log file: /var/log/terminas.log"
    echo "  - Service: terminas-monitor.service (running)"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo ""
    echo -e "${YELLOW}You can safely remove old paths after verifying everything works:${NC}"
    echo "  sudo rm -rf /var/backups/scripts"
    echo "  sudo rm /var/log/backup_monitor.log*"
    echo "  sudo rm /etc/logrotate.d/terminas-monitor"
    echo ""
    echo "Monitor logs: tail -f /var/log/terminas.log"
else
    echo -e "${RED}Migration completed with $ERRORS error(s)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Please review the errors above and check:"
    echo "  - Service logs: journalctl -u terminas-monitor.service -n 50"
    echo "  - System logs: tail /var/log/syslog"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo ""
    echo -e "${YELLOW}You can restore from backup if needed:${NC}"
    echo "  sudo systemctl stop terminas-monitor.service"
    echo "  sudo cp -a $BACKUP_DIR/scripts-old/* /var/backups/scripts/"
    echo "  sudo cp $BACKUP_DIR/terminas-monitor.service.old /etc/systemd/system/terminas-monitor.service"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl start terminas-monitor.service"
fi
