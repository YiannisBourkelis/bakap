#!/bin/bash

# setup.sh - Setup script for Debian backup server with versioning support
# This script configures a Debian system to allow remote clients to upload files via SCP/SFTP
# with automatic versioning for ransomware protection.
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/bakap

set -e

echo "Starting backup server setup..."

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y openssh-server pwgen cron inotify-tools rsync fail2ban

# Create backup users group
echo "Creating backupusers group..."
groupadd -f backupusers

# Configure SSH
echo "Configuring SSH..."

# Only modify if not already set
if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    echo "  - Set PermitRootLogin to no"
fi

if ! grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    echo "  - Enabled PasswordAuthentication"
fi

# Enable internal-sftp subsystem (check if already configured)
if ! grep -q "Subsystem sftp internal-sftp" /etc/ssh/sshd_config; then
    sed -i 's/#*Subsystem sftp.*/Subsystem sftp internal-sftp/' /etc/ssh/sshd_config
    echo "  - Configured internal-sftp subsystem"
fi

# Add group chroot configuration (only if not already present)
if ! grep -q "Match Group backupusers" /etc/ssh/sshd_config; then
    echo "" >> /etc/ssh/sshd_config
    echo "# Bakap backup users configuration" >> /etc/ssh/sshd_config
    echo "Match Group backupusers" >> /etc/ssh/sshd_config
    echo "    ChrootDirectory %h" >> /etc/ssh/sshd_config
    echo "    ForceCommand internal-sftp" >> /etc/ssh/sshd_config
    echo "    AllowTcpForwarding no" >> /etc/ssh/sshd_config
    echo "    X11Forwarding no" >> /etc/ssh/sshd_config
    echo "  - Added backupusers chroot configuration"
fi

# Restart SSH
echo "Restarting SSH service..."
systemctl restart ssh

# Configure fail2ban for SSH/SFTP protection
echo "Configuring fail2ban..."

# Detect the correct auth log path
if [ -f /var/log/auth.log ]; then
    AUTH_LOG="/var/log/auth.log"
elif [ -f /var/log/secure ]; then
    AUTH_LOG="/var/log/secure"
else
    # Create auth.log if it doesn't exist
    touch /var/log/auth.log
    AUTH_LOG="/var/log/auth.log"
fi

if [ ! -f /etc/fail2ban/jail.d/bakap-sshd.conf ]; then
    cat > /etc/fail2ban/jail.d/bakap-sshd.conf <<F2B
# Bakap fail2ban configuration for SSH/SFTP protection
# This protects both SSH and SFTP since SFTP uses SSH authentication

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = $AUTH_LOG
backend = systemd
maxretry = 5
bantime = 3600
findtime = 600
action = iptables-allports[name=sshd]

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = $AUTH_LOG
backend = systemd
maxretry = 10
bantime = 600
findtime = 60
action = iptables-allports[name=sshd-ddos]
F2B
    echo "  - Created fail2ban SSH/SFTP jail configuration (using $AUTH_LOG)"
else
    echo "  - fail2ban SSH/SFTP jail configuration already exists"
fi

# Create sshd-ddos filter for connection flooding protection
if [ ! -f /etc/fail2ban/filter.d/sshd-ddos.conf ]; then
    cat > /etc/fail2ban/filter.d/sshd-ddos.conf <<'FILTER'
# Bakap filter for SSH/SFTP DOS (connection flooding) protection
# Detects rapid connection attempts that may indicate a DOS attack
[Definition]
failregex = ^.*Did not receive identification string from <HOST>.*$
            ^.*Connection closed by <HOST> port \d+ \[preauth\].*$
            ^.*Connection reset by <HOST> port \d+ \[preauth\].*$
            ^.*SSH: Server;Ltype: Version;Remote: <HOST>-\d+;.*$
ignoreregex =
FILTER
    echo "  - Created sshd-ddos filter"
fi

# Create custom filter for SFTP-specific issues if needed
if [ ! -f /etc/fail2ban/filter.d/bakap-sftp.conf ]; then
    cat > /etc/fail2ban/filter.d/bakap-sftp.conf <<'FILTER'
# Bakap custom filter for SFTP abuse
[Definition]
failregex = ^.*subsystem request for sftp.*Failed password for .* from <HOST>.*$
            ^.*subsystem request for sftp.*Connection closed by authenticating user .* <HOST>.*\[preauth\]$
ignoreregex =
FILTER
    echo "  - Created custom SFTP abuse filter"
fi

# Enable and start fail2ban
echo "Starting fail2ban service..."
systemctl enable fail2ban
systemctl restart fail2ban
echo "  - fail2ban is now protecting SSH/SFTP:"
echo "    * 5 failed login attempts = 1 hour ban"
echo "    * 10 connection attempts in 60s = 10 minute ban (DOS protection)"
echo "    * Applies to both SSH and SFTP connections"


# Create base directories
echo "Creating base directories..."
mkdir -p /var/backups/scripts

# Create monitor script for real-time incremental snapshots
echo "Creating/updating monitor script..."
cat > /var/backups/scripts/monitor_backups.sh <<'EOF'
#!/bin/bash
# Real-time monitor script for user backups
# Watches /home and filters events under uploads/ so new users/uploads are picked up even after start
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/bakap

LOG=/var/log/backup_monitor.log
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown root:adm "$LOG" 2>/dev/null || true
chmod 640 "$LOG" 2>/dev/null || true

# Watch /home recursively and react to close_write and moved_to events only
# close_write: fired when a file is written and closed (upload complete)
# moved_to: fired when a file is moved into the directory
# We deliberately exclude 'create' to avoid snapshotting partial files during long uploads
inotifywait -m -r /home -e close_write -e moved_to --format '%w%f %e' |
while read path event; do
    # Only handle events that happen inside an uploads directory
    case "$path" in
        */uploads|*/uploads/*)
            ;;
        *)
            continue
            ;;
    esac

    # Extract username from path: /home/<user>/uploads/...
    user=$(echo "$path" | awk -F/ '{print $3}')
    if [ -z "$user" ]; then
        continue
    fi

    if [ ! -d "/home/$user/uploads" ]; then
        # uploads dir might have been removed
        continue
    fi

    # Debounce: avoid creating multiple snapshots for rapidly repeated events
    # Since we only watch close_write events, files are already fully written when we see them
    # BAKAP_DEBOUNCE_SECONDS - time window to coalesce multiple file uploads (default 15)
    #   If another file completes within this window, reset the timer
    # BAKAP_SNAPSHOT_DELAY - additional seconds to wait after last close_write (default 10)
    #   Ensures batch uploads (multiple files) are captured in one snapshot
    # For very large batch uploads (100+ files), increase DEBOUNCE_SECONDS
    DEBOUNCE_SECONDS=${BAKAP_DEBOUNCE_SECONDS:-15}
    SLEEP_SECONDS=${BAKAP_SNAPSHOT_DELAY:-10}
    # Use a small per-user timestamp file in /var/run
    runstamp_dir=/var/run/bakap
    mkdir -p "$runstamp_dir"
    lastfile="$runstamp_dir/last_$user"
    now=$(date +%s)
    if [ -f "$lastfile" ]; then
        last=$(cat "$lastfile" 2>/dev/null || echo 0)
    else
        last=0
    fi
    # If we created a snapshot less than DEBOUNCE_SECONDS ago, skip (coalesce)
    if [ $((now - last)) -lt "$DEBOUNCE_SECONDS" ]; then
        # update the timestamp so subsequent events extend the window
        echo "$now" > "$lastfile" 2>/dev/null || true
        continue
    fi
    # wait a short moment to let other file operations settle
    sleep "$SLEEP_SECONDS"
    
    # Check if uploads directory has any files before creating snapshot
    if [ -z "$(ls -A "/home/$user/uploads" 2>/dev/null)" ]; then
        echo "$(date '+%F %T') Skipping snapshot for $user: uploads directory is empty" >> "$LOG"
        date +%s > "$lastfile" 2>/dev/null || true
        continue
    fi
    
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    snapshot_dir="/home/$user/versions/$timestamp"
    mkdir -p "$snapshot_dir"

    latest_snapshot=$(ls -d /home/$user/versions/* 2>/dev/null | sort | tail -1)

    if [ -n "$latest_snapshot" ]; then
        rsync -a --link-dest="$latest_snapshot" "/home/$user/uploads/" "$snapshot_dir/"
    else
        rsync -a "/home/$user/uploads/" "$snapshot_dir/"
    fi

    chown -R root:root "$snapshot_dir" || true
    chmod -R 755 "$snapshot_dir" || true
    echo "$(date '+%F %T') Incremental snapshot created for $user at $timestamp due to $event" >> "$LOG"
    # record last snapshot time
    date +%s > "$lastfile" 2>/dev/null || true
done
EOF

chmod +x /var/backups/scripts/monitor_backups.sh

# Create systemd unit for the monitor (preserve Environment variables if service exists)
echo "Installing systemd unit for backup monitor..."
if [ -f /etc/systemd/system/bakap-monitor.service ]; then
    # Extract existing Environment variables
    existing_env=$(grep "^Environment=" /etc/systemd/system/bakap-monitor.service 2>/dev/null || true)
    cat > /etc/systemd/system/bakap-monitor.service <<'UNIT'
[Unit]
Description=Bakap real-time backup monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /var/backups/scripts/monitor_backups.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
    # Re-add any existing Environment variables
    if [ -n "$existing_env" ]; then
        # Insert Environment lines after [Service] line
        sed -i "/^\[Service\]/a $existing_env" /etc/systemd/system/bakap-monitor.service
        echo "  - Preserved existing environment variables"
    fi
else
    cat > /etc/systemd/system/bakap-monitor.service <<'UNIT'
[Unit]
Description=Bakap real-time backup monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /var/backups/scripts/monitor_backups.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
fi

systemctl daemon-reload
systemctl enable --now bakap-monitor.service

# Tune inotify max_user_watches to support many users/directories
if [ ! -f /etc/sysctl.d/99-bakap-inotify.conf ]; then
    echo "Configuring inotify limits..."
    echo "fs.inotify.max_user_watches=524288" > /etc/sysctl.d/99-bakap-inotify.conf
    sysctl --system >/dev/null 2>&1 || true
fi

# Add logrotate config for the monitor log
echo "Configuring log rotation..."
cat > /etc/logrotate.d/bakap-monitor <<'LR'
/var/log/backup_monitor.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 640 root adm
}
LR

# Create retention policy configuration file (only if it doesn't exist)
if [ ! -f /etc/bakap-retention.conf ]; then
    echo "Creating retention policy configuration..."
    cat > /etc/bakap-retention.conf <<'CONF'
# Bakap Retention Policy Configuration
# Edit this file to customize snapshot retention

# Default retention mode: advanced (recommended)
# Set to 'false' to use simple age-based retention
ENABLE_ADVANCED_RETENTION=true

# Simple age-based retention (days) - used when ENABLE_ADVANCED_RETENTION=false
# Snapshots older than this will be deleted
RETENTION_DAYS=30

# Advanced retention policy (Grandfather-Father-Son strategy)
# Keep: last N daily, last M weekly, last Y monthly snapshots
KEEP_DAILY=7        # Keep last 7 daily snapshots
KEEP_WEEKLY=4       # Keep last 4 weekly snapshots (one per week)
KEEP_MONTHLY=6      # Keep last 6 monthly snapshots (one per month)

# Per-user overrides (optional)
# Format: USERNAME_KEEP_DAILY=N, USERNAME_KEEP_WEEKLY=M, USERNAME_KEEP_MONTHLY=Y
# Example:
#   produser_KEEP_DAILY=30
#   produser_KEEP_WEEKLY=12
#   produser_KEEP_MONTHLY=24
#   testuser_RETENTION_DAYS=7
#   testuser_ENABLE_ADVANCED_RETENTION=false

# Run cleanup at this hour (0-23)
CLEANUP_HOUR=3
CONF
else
    echo "Retention policy configuration already exists, preserving existing settings"
fi

# Create/update cleanup script with configurable retention
echo "Creating/updating cleanup script..."
cat > /var/backups/scripts/cleanup_snapshots.sh <<'EOF'
#!/bin/bash
# Cleanup old snapshots based on retention policy
# Configuration: /etc/bakap-retention.conf
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/bakap

# Load configuration
if [ -f /etc/bakap-retention.conf ]; then
    source /etc/bakap-retention.conf
else
    # Defaults if config file is missing
    RETENTION_DAYS=30
    ENABLE_ADVANCED_RETENTION=false
fi

LOG=/var/log/backup_monitor.log

log_msg() {
    echo "$(date '+%F %T') [CLEANUP] $*" >> "$LOG"
}

# Simple age-based cleanup
cleanup_by_age() {
    log_msg "Running age-based cleanup (keeping last $RETENTION_DAYS days)"
    local count=0
    while IFS= read -r -d '' snapshot; do
        rm -rf "$snapshot"
        count=$((count + 1))
    done < <(find /home -mindepth 2 -maxdepth 3 -type d -path '*/versions/*' -mtime +$RETENTION_DAYS -print0 2>/dev/null)
    log_msg "Removed $count snapshots older than $RETENTION_DAYS days"
}

# Advanced retention: keep daily, weekly, monthly snapshots
cleanup_advanced() {
    log_msg "Running advanced retention cleanup (default: daily=$KEEP_DAILY, weekly=$KEEP_WEEKLY, monthly=$KEEP_MONTHLY)"
    
    # Get list of backup users
    local users=$(getent group backupusers 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^$')
    
    while IFS= read -r user; do
        [ -z "$user" ] && continue
        local versions_dir="/home/$user/versions"
        [ ! -d "$versions_dir" ] && continue
        
        # Check for per-user retention settings
        local user_daily_var="${user}_KEEP_DAILY"
        local user_weekly_var="${user}_KEEP_WEEKLY"
        local user_monthly_var="${user}_KEEP_MONTHLY"
        local user_daily=${!user_daily_var:-$KEEP_DAILY}
        local user_weekly=${!user_weekly_var:-$KEEP_WEEKLY}
        local user_monthly=${!user_monthly_var:-$KEEP_MONTHLY}
        
        if [ "$user_daily" != "$KEEP_DAILY" ] || [ "$user_weekly" != "$KEEP_WEEKLY" ] || [ "$user_monthly" != "$KEEP_MONTHLY" ]; then
            log_msg "User $user: using custom retention (daily=$user_daily, weekly=$user_weekly, monthly=$user_monthly)"
        fi
        
        # Get all snapshots sorted by date (newest first)
        local snapshots=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
        [ -z "$snapshots" ] && continue
        
        # Arrays to track what to keep
        declare -A keep_snapshots
        local snapshot_array=()
        while IFS= read -r s; do
            [ -n "$s" ] && snapshot_array+=("$s")
        done <<< "$snapshots"
        
        # Keep last N daily snapshots
        local daily_count=0
        for snapshot in "${snapshot_array[@]}"; do
            [ $daily_count -ge $user_daily ] && break
            keep_snapshots["$snapshot"]=1
            daily_count=$((daily_count + 1))
        done
        
        # Keep last N weekly snapshots (one per week)
        local weekly_count=0
        local last_week=""
        for snapshot in "${snapshot_array[@]}"; do
            [ $weekly_count -ge $user_weekly ] && break
            # Extract date from snapshot name (format: YYYY-MM-DD_HH-MM-SS)
            local snap_date=$(basename "$snapshot" | cut -d_ -f1)
            local week=$(date -d "$snap_date" +%Y-W%U 2>/dev/null || echo "")
            if [ -n "$week" ] && [ "$week" != "$last_week" ]; then
                keep_snapshots["$snapshot"]=1
                last_week="$week"
                weekly_count=$((weekly_count + 1))
            fi
        done
        
        # Keep last N monthly snapshots (one per month)
        local monthly_count=0
        local last_month=""
        for snapshot in "${snapshot_array[@]}"; do
            [ $monthly_count -ge $user_monthly ] && break
            local snap_date=$(basename "$snapshot" | cut -d_ -f1)
            local month=$(date -d "$snap_date" +%Y-%m 2>/dev/null || echo "")
            if [ -n "$month" ] && [ "$month" != "$last_month" ]; then
                keep_snapshots["$snapshot"]=1
                last_month="$month"
                monthly_count=$((monthly_count + 1))
            fi
        done
        
        # Remove snapshots not in keep list
        local removed=0
        for snapshot in "${snapshot_array[@]}"; do
            if [ -z "${keep_snapshots[$snapshot]}" ]; then
                rm -rf "$snapshot"
                removed=$((removed + 1))
            fi
        done
        
        [ $removed -gt 0 ] && log_msg "User $user: removed $removed snapshots"
    done
}

# Main cleanup logic
if [ "$ENABLE_ADVANCED_RETENTION" = "true" ]; then
    cleanup_advanced
else
    cleanup_by_age
fi

log_msg "Cleanup completed"
EOF
chmod +x /var/backups/scripts/cleanup_snapshots.sh

# Install daily cron job for cleanup (run at configured hour) - only if not already present
if ! crontab -l 2>/dev/null | grep -q "cleanup_snapshots.sh"; then
    echo "Installing cleanup cron job..."
    (crontab -l 2>/dev/null; echo "0 3 * * * /var/backups/scripts/cleanup_snapshots.sh") | crontab -
else
    echo "Cleanup cron job already exists"
fi

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Create backup users: ./create_user.sh <username>"
echo "  2. Monitor logs: tail -f /var/log/backup_monitor.log"
echo "  3. Check service: systemctl status bakap-monitor.service"
echo "  4. Manage users: ./manage_users.sh list"
echo ""
echo "Configuration files:"
echo "  - Retention policy: /etc/bakap-retention.conf"
echo "  - Monitor service: /etc/systemd/system/bakap-monitor.service"
echo "  - Scripts: /var/backups/scripts/"
echo ""