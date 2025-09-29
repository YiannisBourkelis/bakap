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
# Real-time queued monitor script for user backups
# This implementation writes a per-user pending marker when uploads/ events occur
# and a background worker snapshots each pending user once every DEBOUNCE_SECONDS.

LOG=/var/log/backup_monitor.log
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown root:adm "$LOG" 2>/dev/null || true
chmod 640 "$LOG" 2>/dev/null || true

# Configurable via environment variables
# QUIET_SECONDS: require this many seconds with no file events before snapshotting (default 60)
# WORKER_POLL: how often worker wakes up to check pending users (default 5s)
QUIET_SECONDS=${BAKAP_QUIET_SECONDS:-60}
WORKER_POLL=${BAKAP_WORKER_POLL:-5}
PENDING_DIR=/var/run/bakap/pending
mkdir -p "$PENDING_DIR"
chown root:root "$PENDING_DIR" 2>/dev/null || true
chmod 755 "$PENDING_DIR" 2>/dev/null || true

trace() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null || true; }

# Worker: periodically look for pending users and snapshot them once
worker() {
    while true; do
        now=$(date +%s)
        for tsfile in "$PENDING_DIR"/*; do
            [ -e "$tsfile" ] || continue
            user=$(basename "$tsfile")
            last=$(cat "$tsfile" 2>/dev/null || echo 0)
            # if last is not numeric, skip
            if ! printf '%s' "$last" | grep -Eq '^[0-9]+$'; then
                # remove malformed file
                rm -f "$tsfile" 2>/dev/null || true
                continue
            fi
            age=$(( now - last ))
            if [ $age -lt "$QUIET_SECONDS" ]; then
                # not quiet yet; skip
                continue
            fi
            # it's been QUIET_SECONDS since last change; snapshot now
            rm -f "$tsfile" 2>/dev/null || true
            if [ ! -d "/home/$user/uploads" ]; then
                trace "No uploads dir for $user, skipping"
                continue
            fi
            timestamp=$(date +%Y%m%d%H%M%S)
            snapshot_dir="/home/$user/versions/$timestamp"
            mkdir -p "$snapshot_dir"
            latest_snapshot=$(ls -d /home/$user/versions/* 2>/dev/null | sort | tail -1)
            if [ -n "$latest_snapshot" ]; then
                if cp -al "$latest_snapshot" "$snapshot_dir" 2>/dev/null; then
                    rsync -a --delete "/home/$user/uploads/" "$snapshot_dir/"
                else
                    rsync -a --link-dest="$latest_snapshot" "/home/$user/uploads/" "$snapshot_dir/"
                fi
            else
                rsync -a "/home/$user/uploads/" "$snapshot_dir/"
            fi
            chown -R root:root "$snapshot_dir" || true
            chmod -R 755 "$snapshot_dir" || true
            trace "Snapshot created for $user at $timestamp (age ${age}s)"
        done
        sleep "$WORKER_POLL"
    done
}

# Start worker in background
worker &
WORKER_PID=$!
trace "Started worker pid=$WORKER_PID"

# Monitor: write a per-user pending marker on relevant events under uploads/
inotifywait -m -r /home -e close_write -e moved_to -e create --format '%w%f %e' | while read path event; do
    case "$path" in
        */uploads|*/uploads/*)
            ;;
        *)
            continue
            ;;
    esac
    user=$(echo "$path" | awk -F/ '{print $3}')
    if [ -z "$user" ]; then
        continue
    fi
    # record last-event epoch (atomic)
    echo "$(date +%s)" > "$PENDING_DIR/$user"
    trace "Recorded event for $user at $(cat $PENDING_DIR/$user) due to $event on $path"
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