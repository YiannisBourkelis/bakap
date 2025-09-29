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
apt install -y openssh-server pwgen cron inotify-tools rsync fail2ban

# Create backup users group
echo "Creating backupusers group..."
groupadd -f backupusers

# Configure scponly for restricted access (SCP/SFTP only) with chroot
echo "Configuring scponly..."
cat > /etc/scponly.conf <<EOF
# scponly configuration file

# Shell to use for chrooted users
SHELL=/usr/bin/scponly

# Directory where user home directories are located
# This should match the chroot directory in /etc/ssh/sshd_config
CHROOT_DIR=/home

# Log facility for scponly
LOG_FACILITY=LOG_USER
EOF

# Configure SSH
echo "Configuring SSH..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Add group for chroot
echo "Match Group backupusers" >> /etc/ssh/sshd_config
echo "    ChrootDirectory %h" >> /etc/ssh/sshd_config
echo "    AllowTcpForwarding no" >> /etc/ssh/sshd_config
echo "    X11Forwarding no" >> /etc/ssh/sshd_config

# Restart SSH
echo "Restarting SSH service..."
systemctl restart ssh

# Configure and start fail2ban for SSH protection
echo "Configuring fail2ban for SSH protection..."
systemctl enable --now fail2ban

echo "Fail2ban is now monitoring SSH logins."

# Create base directories
echo "Creating base directories..."
mkdir -p /var/backups/scripts

# Create monitor script for real-time incremental snapshots
echo "Creating monitor script..."
cat > /var/backups/scripts/monitor_backups.sh <<'EOF'
#!/bin/bash
# Real-time monitor script for user backups
# Uses inotify and rsync to create incremental snapshots on changes

inotifywait -m -r /home/*/uploads --format '%w %e' | while read dir event; do
    if [[ $event =~ (CREATE|DELETE|MODIFY|MOVED_TO|MOVED_FROM) ]]; then
        user=$(basename $(dirname "$dir"))
        if [ -d "/home/$user/uploads" ]; then
            timestamp=$(date +%Y%m%d%H%M%S)
            snapshot_dir="/home/$user/versions/$timestamp"
            mkdir -p "$snapshot_dir"
            
            # Find the latest previous snapshot
            latest_snapshot=$(ls -d /home/$user/versions/* 2>/dev/null | sort | tail -1)
            
            if [ -n "$latest_snapshot" ]; then
                # Incremental snapshot using rsync with link-dest
                rsync -a --link-dest="$latest_snapshot" "/home/$user/uploads/" "$snapshot_dir/"
            else
                # First snapshot, full copy
                rsync -a "/home/$user/uploads/" "$snapshot_dir/"
            fi
            
            chown -R root:root "$snapshot_dir"
            chmod -R 755 "$snapshot_dir"
            echo "Incremental snapshot created for $user at $timestamp due to $event"
        fi
    fi
done
EOF

chmod +x /var/backups/scripts/monitor_backups.sh

# Start the monitor as a background service
echo "Starting real-time monitor service..."
nohup /var/backups/scripts/monitor_backups.sh > /var/log/backup_monitor.log 2>&1 &

# Remove the old cron job
(crontab -l 2>/dev/null | grep -v snapshot_backups.sh) | crontab -

echo "Setup complete!"
echo "Use create_user.sh <username> to create backup users."