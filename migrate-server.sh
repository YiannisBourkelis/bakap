#!/bin/bash
#
# Quick Migration Script: bakap → termiNAS
# Copyright (c) 2025 Yianni Bourkelis
# MIT License
#
# This script automates the migration of an existing bakap installation to termiNAS
# Run on the remote server where bakap is installed in /opt/bakap
#
# Usage: sudo ./migrate-server.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=================================================="
echo "termiNAS Server Migration Script"
echo "=================================================="
echo -e "Migrating: bakap → termiNAS${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if /opt/bakap exists
if [ ! -d /opt/bakap ]; then
    echo -e "${RED}ERROR: /opt/bakap directory not found${NC}"
    echo "Is bakap installed on this server?"
    exit 1
fi

# Confirmation
echo -e "${YELLOW}⚠️  WARNING: This will migrate your bakap installation to termiNAS${NC}"
echo ""
echo "Changes to be made:"
echo "  - Stop bakap-monitor.service"
echo "  - Rename configuration files"
echo "  - Update systemd services"
echo "  - Rename /opt/bakap to /opt/terminas"
echo "  - Update git repository URL"
echo "  - Restart services with new names"
echo ""
echo "User data (/home/*/uploads, /home/*/versions) will NOT be affected."
echo ""
read -p "Continue with migration? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Migration cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}Starting migration...${NC}"
echo ""

# Step 1: Create backup
BACKUP_DIR="/backup/bakap-to-terminas-$(date +%Y%m%d-%H%M%S)"
echo -e "${CYAN}[1/15] Creating backup in $BACKUP_DIR${NC}"
mkdir -p "$BACKUP_DIR"
cp /etc/bakap-retention.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/systemd/system/bakap-monitor.service "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/fail2ban/jail.d/bakap-*.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/fail2ban/filter.d/bakap-*.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/fail2ban/action.d/nftables-bakap.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/logrotate.d/bakap-monitor "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/sysctl.d/99-bakap-inotify.conf "$BACKUP_DIR/" 2>/dev/null || true
cp -r /var/backups/scripts "$BACKUP_DIR/" 2>/dev/null || true
cd /opt/bakap && git status > "$BACKUP_DIR/git-status.txt" && git remote -v > "$BACKUP_DIR/git-remote.txt"
echo -e "${GREEN}✓ Backup created${NC}"

# Step 2: Stop services
echo -e "${CYAN}[2/15] Stopping bakap-monitor.service${NC}"
systemctl stop bakap-monitor.service
echo -e "${GREEN}✓ Service stopped${NC}"

# Step 3: Update git repository
echo -e "${CYAN}[3/15] Updating git repository${NC}"
cd /opt/bakap
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
git fetch origin
git pull origin main
echo -e "${GREEN}✓ Git repository updated${NC}"

# Step 4: Rename configuration files
echo -e "${CYAN}[4/15] Renaming configuration files${NC}"
if [ -f /etc/bakap-retention.conf ]; then
    mv /etc/bakap-retention.conf /etc/terminas-retention.conf
    sed -i 's/bakap/terminas/g' /etc/terminas-retention.conf
    sed -i 's/BAKAP/TERMINAS/g' /etc/terminas-retention.conf
    echo -e "${GREEN}✓ Renamed retention config${NC}"
fi

# Step 5: Rename systemd service
echo -e "${CYAN}[5/15] Renaming systemd service${NC}"
mv /etc/systemd/system/bakap-monitor.service /etc/systemd/system/terminas-monitor.service
sed -i 's/bakap/terminas/g' /etc/systemd/system/terminas-monitor.service
sed -i 's/BAKAP/TERMINAS/g' /etc/systemd/system/terminas-monitor.service
sed -i 's/Bakap/termiNAS/g' /etc/systemd/system/terminas-monitor.service
systemctl daemon-reload
echo -e "${GREEN}✓ Service renamed${NC}"

# Step 6: Update and migrate monitor scripts
echo -e "${CYAN}[6/15] Updating and migrating monitor scripts${NC}"

# Create new directory structure
mkdir -p /var/terminas/scripts

# Migrate and rename scripts
if [ -f /var/backups/scripts/monitor_backups.sh ]; then
    # Update content then move with new name
    sed -i 's/bakap/terminas/g' /var/backups/scripts/monitor_backups.sh
    sed -i 's/BAKAP/TERMINAS/g' /var/backups/scripts/monitor_backups.sh
    sed -i 's/Bakap/termiNAS/g' /var/backups/scripts/monitor_backups.sh
    sed -i 's/backup_monitor\.log/terminas.log/g' /var/backups/scripts/monitor_backups.sh
    mv /var/backups/scripts/monitor_backups.sh /var/terminas/scripts/terminas-monitor.sh
    chmod +x /var/terminas/scripts/terminas-monitor.sh
    echo "  - Migrated: monitor_backups.sh → terminas-monitor.sh"
fi

if [ -f /var/backups/scripts/cleanup_snapshots.sh ]; then
    sed -i 's/bakap/terminas/g' /var/backups/scripts/cleanup_snapshots.sh
    sed -i 's/BAKAP/TERMINAS/g' /var/backups/scripts/cleanup_snapshots.sh
    sed -i 's/Bakap/termiNAS/g' /var/backups/scripts/cleanup_snapshots.sh
    sed -i 's/backup_monitor\.log/terminas.log/g' /var/backups/scripts/cleanup_snapshots.sh
    mv /var/backups/scripts/cleanup_snapshots.sh /var/terminas/scripts/terminas-cleanup.sh
    chmod +x /var/terminas/scripts/terminas-cleanup.sh
    echo "  - Migrated: cleanup_snapshots.sh → terminas-cleanup.sh"
fi

# Update systemd service to use new script path
sed -i 's|/var/backups/scripts/monitor_backups.sh|/var/terminas/scripts/terminas-monitor.sh|g' \
    /etc/systemd/system/terminas-monitor.service

# Update crontab for cleanup script
if crontab -l 2>/dev/null | grep -q "cleanup_snapshots.sh"; then
    crontab -l 2>/dev/null | \
        sed 's|/var/backups/scripts/cleanup_snapshots.sh|/var/terminas/scripts/terminas-cleanup.sh|g' | \
        crontab -
    echo "  - Updated crontab to use terminas-cleanup.sh"
fi

echo -e "${GREEN}✓ Scripts migrated to /var/terminas/scripts/${NC}"

# Step 7: Rename runtime directories
echo -e "${CYAN}[7/15] Renaming runtime directories${NC}"
mkdir -p /var/run/terminas
if [ -d /var/run/bakap ]; then
    mv /var/run/bakap/* /var/run/terminas/ 2>/dev/null || true
    rmdir /var/run/bakap
fi
chmod 755 /var/run/terminas
echo -e "${GREEN}✓ Runtime directories updated${NC}"

# Step 8: Update log configuration
echo -e "${CYAN}[8/15] Migrating log files and configuration${NC}"

# Migrate log file
if [ -f /var/log/backup_monitor.log ]; then
    cp /var/log/backup_monitor.log /var/log/terminas.log
    chown root:adm /var/log/terminas.log 2>/dev/null || true
    chmod 640 /var/log/terminas.log 2>/dev/null || true
    echo "  - Migrated: backup_monitor.log → terminas.log"
fi

# Update logrotate config with new name and path
if [ -f /etc/logrotate.d/bakap-monitor ]; then
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
    echo "  - Created: /etc/logrotate.d/terminas"
fi

echo -e "${GREEN}✓ Logs migrated to /var/log/terminas.log${NC}"

# Step 9: Update inotify configuration
echo -e "${CYAN}[9/15] Updating inotify configuration${NC}"
if [ -f /etc/sysctl.d/99-bakap-inotify.conf ]; then
    mv /etc/sysctl.d/99-bakap-inotify.conf /etc/sysctl.d/99-terminas-inotify.conf
    echo -e "${GREEN}✓ Inotify config updated${NC}"
fi

# Step 10: Update fail2ban configurations
echo -e "${CYAN}[10/15] Updating fail2ban configurations${NC}"
for f in /etc/fail2ban/jail.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        mv "$f" "$newf"
        sed -i 's/bakap/terminas/g' "$newf"
        sed -i 's/\[bakap-/\[terminas-/g' "$newf"
        sed -i 's/Bakap/termiNAS/g' "$newf"
    fi
done

for f in /etc/fail2ban/filter.d/bakap-*.conf; do
    if [ -f "$f" ]; then
        newf=$(echo "$f" | sed 's/bakap-/terminas-/g')
        mv "$f" "$newf"
        sed -i 's/bakap/terminas/g' "$newf"
        sed -i 's/Bakap/termiNAS/g' "$newf"
    fi
done

if [ -f /etc/fail2ban/action.d/nftables-bakap.conf ]; then
    mv /etc/fail2ban/action.d/nftables-bakap.conf /etc/fail2ban/action.d/nftables-terminas.conf
    sed -i 's/bakap/terminas/g' /etc/fail2ban/action.d/nftables-terminas.conf
fi
echo -e "${GREEN}✓ fail2ban configs updated${NC}"

# Step 11: Restart fail2ban
echo -e "${CYAN}[11/15] Restarting fail2ban${NC}"
systemctl restart fail2ban
echo -e "${GREEN}✓ fail2ban restarted${NC}"

# Step 12: Update SSH configuration
echo -e "${CYAN}[12/15] Updating SSH configuration${NC}"
sed -i 's/# Bakap backup users/# termiNAS backup users/g' /etc/ssh/sshd_config
echo -e "${GREEN}✓ SSH config updated${NC}"

# Step 13: Update Samba (if configured)
echo -e "${CYAN}[13/15] Updating Samba configuration (if present)${NC}"
if grep -q "Bakap" /etc/samba/smb.conf 2>/dev/null; then
    sed -i 's/Bakap Backup Server/termiNAS Backup Server/g' /etc/samba/smb.conf
    sed -i 's/Bakap backup/termiNAS backup/g' /etc/samba/smb.conf
    systemctl restart smbd nmbd 2>/dev/null || true
    echo -e "${GREEN}✓ Samba updated${NC}"
else
    echo -e "${YELLOW}ℹ Samba not configured${NC}"
fi

# Step 14: Rename installation directory
echo -e "${CYAN}[14/15] Renaming installation directory${NC}"
cd /opt
mv bakap terminas
echo -e "${GREEN}✓ Directory renamed: /opt/bakap → /opt/terminas${NC}"

# Step 15: Start termiNAS services
echo -e "${CYAN}[15/15] Starting termiNAS services${NC}"
systemctl enable terminas-monitor.service
systemctl start terminas-monitor.service
echo -e "${GREEN}✓ Services started${NC}"

echo ""
echo -e "${GREEN}=================================================="
echo "✓ Migration Complete!"
echo "==================================================${NC}"
echo ""
echo -e "${CYAN}Verification:${NC}"
echo "  Service status: systemctl status terminas-monitor.service"
echo "  View logs:      tail -f /var/log/terminas.log"
echo "  List users:     /opt/terminas/src/server/manage_users.sh list"
echo ""
echo -e "${CYAN}Backup location:${NC}"
echo "  $BACKUP_DIR"
echo ""
echo -e "${CYAN}Git repository:${NC}"
echo "  https://github.com/YiannisBourkelis/termiNAS"
echo ""

# Final verification
echo -e "${CYAN}Running verification checks...${NC}"
echo ""

if systemctl is-active --quiet terminas-monitor.service; then
    echo -e "${GREEN}✓ terminas-monitor.service is running${NC}"
else
    echo -e "${RED}✗ terminas-monitor.service is NOT running${NC}"
    echo "  Check: systemctl status terminas-monitor.service"
fi

if systemctl is-active --quiet fail2ban; then
    echo -e "${GREEN}✓ fail2ban is running${NC}"
else
    echo -e "${RED}✗ fail2ban is NOT running${NC}"
fi

if [ -f /etc/terminas-retention.conf ]; then
    echo -e "${GREEN}✓ /etc/terminas-retention.conf exists${NC}"
else
    echo -e "${RED}✗ /etc/terminas-retention.conf NOT found${NC}"
fi

if [ -d /opt/terminas ]; then
    echo -e "${GREEN}✓ /opt/terminas exists${NC}"
else
    echo -e "${RED}✗ /opt/terminas NOT found${NC}"
fi

echo ""
echo -e "${GREEN}Migration successful! Your server is now running termiNAS.${NC}"
echo ""
echo -e "${YELLOW}Note: User data in /home/*/uploads and /home/*/versions is unchanged.${NC}"
echo -e "${YELLOW}Users can continue connecting via SFTP with the same credentials.${NC}"
echo ""
