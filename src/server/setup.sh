#!/bin/bash

# setup.sh - Setup script for Debian backup server with versioning support
# This script configures a Debian system to allow remote clients to upload files via SCP/SFTP
# with automatic versioning for ransomware protection.

set -e

echo "Starting backup server setup..."

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y openssh-server pwgen cron inotify-tools rsync

# Create backup users group
echo "Creating backupusers group..."
groupadd -f backupusers

# Configure SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#Subsystem sftp /Subsystem sftp /' /etc/ssh/sshd_config
echo "Subsystem sftp internal-sftp" >> /etc/ssh/sshd_config

# Add group for chroot
echo "Match Group backupusers" >> /etc/ssh/sshd_config
echo "    ChrootDirectory %h" >> /etc/ssh/sshd_config
echo "    ForceCommand internal-sftp" >> /etc/ssh/sshd_config
echo "    AllowTcpForwarding no" >> /etc/ssh/sshd_config
echo "    X11Forwarding no" >> /etc/ssh/sshd_config

# Restart SSH
echo "Restarting SSH service..."
systemctl restart ssh

# fail2ban installation/configuration is deferred; install it manually when ready


# Create base directories
echo "Creating base directories..."
mkdir -p /var/backups/scripts

echo "Creating monitor script..."
# Create monitor script for real-time incremental snapshots
echo "Creating monitor script..."
cat > /var/backups/scripts/monitor_backups.sh <<'EOF'
#!/bin/bash
# Real-time monitor script for user backups
# Watches /home and filters events under uploads/ so new users/uploads are picked up even after start

LOG=/var/log/backup_monitor.log
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown root:adm "$LOG" 2>/dev/null || true
chmod 640 "$LOG" 2>/dev/null || true

# Watch /home recursively and react to close_write/moved_to/create events
inotifywait -m -r /home -e close_write -e moved_to -e create --format '%w%f %e' |
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
    # Configurable via environment variables when running the monitor
    # BAKAP_DEBOUNCE_SECONDS - time window to coalesce events (default 5)
    # BAKAP_SNAPSHOT_DELAY - seconds to wait before snapshotting to let writes settle (default 3)
    DEBOUNCE_SECONDS=${BAKAP_DEBOUNCE_SECONDS:-5}
    SLEEP_SECONDS=${BAKAP_SNAPSHOT_DELAY:-3}
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

# Create systemd unit for the monitor
echo "Installing systemd unit for backup monitor..."
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

systemctl daemon-reload
systemctl enable --now bakap-monitor.service

# Tune inotify max_user_watches to support many users/directories
echo "fs.inotify.max_user_watches=524288" > /etc/sysctl.d/99-bakap-inotify.conf
sysctl --system >/dev/null 2>&1 || true

# Add logrotate config for the monitor log
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

# Create cleanup script to remove snapshots older than 30 days
cat > /var/backups/scripts/cleanup_snapshots.sh <<'EOF'
#!/bin/bash
# Delete user snapshot directories older than 30 days
find /home -mindepth 2 -maxdepth 3 -type d -path '*/versions/*' -mtime +30 -print0 | xargs -0 -r rm -rf
EOF
chmod +x /var/backups/scripts/cleanup_snapshots.sh

# Install daily cron job for cleanup (run at 03:00)
(crontab -l 2>/dev/null; echo "0 3 * * * /var/backups/scripts/cleanup_snapshots.sh") | crontab -

echo "Setup complete!"
echo "Use create_user.sh <username> to create backup users."