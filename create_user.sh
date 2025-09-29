#!/bin/bash

# create_user.sh - Create a backup user with secure password and versioning setup
# Usage: ./create_user.sh <username>

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1

# Check if user exists
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists."
    exit 1
fi

# Generate secure password
PASSWORD=$(pwgen -s 64 1)

echo "Creating user $USERNAME with password: $PASSWORD"
# Create user
useradd -m -g backupusers -s /usr/sbin/nologin "$USERNAME"

# Set the user's password securely. Create a SHA-512 hash and apply it with usermod -p.
# We pass the plain password via stdin to Python to avoid it showing in the process list.
if command -v python3 >/dev/null 2>&1; then
    HASH=$(python3 - <<'PY'
import crypt,sys
pw=sys.stdin.read().rstrip('\n')
print(crypt.crypt(pw, crypt.mksalt(crypt.METHOD_SHA512)))
PY
    ) <<<"$PASSWORD"
    usermod -p "$HASH" "$USERNAME"
elif command -v openssl >/dev/null 2>&1; then
    # Fallback: openssl passwd -6 <password> (may show in process args on some systems)
    HASH=$(openssl passwd -6 "$PASSWORD")
    usermod -p "$HASH" "$USERNAME"
else
    # As a last resort, use chpasswd (note: will fail if password contains a colon ':')
    printf '%s:%s
' "$USERNAME" "$PASSWORD" | chpasswd
fi

# Set ownership for chroot (home must be root-owned)
chown root:root "/home/$USERNAME"
chmod 755 "/home/$USERNAME"

# Create directories
mkdir -p "/home/$USERNAME/uploads"
mkdir -p "/home/$USERNAME/versions"

# Set permissions
# uploads should be writable only by the user
chown "$USERNAME:backupusers" "/home/$USERNAME/uploads"
chmod 700 "/home/$USERNAME/uploads"
# versions are root-owned and not writable by the user
chown root:root "/home/$USERNAME/versions"
chmod 755 "/home/$USERNAME/versions"

echo "User $USERNAME created successfully."
echo "Upload directory: /home/$USERNAME/uploads"
echo "Versions directory: /home/$USERNAME/versions (read-only for user)"
echo "Password: $PASSWORD"
echo "Snapshots are created in real-time on file changes."

# Create an initial one-shot snapshot so the user has a starting point
timestamp=$(date +%Y%m%d%H%M%S)
snapshot_dir="/home/$USERNAME/versions/$timestamp"
mkdir -p "$snapshot_dir"
latest_snapshot=$(ls -d /home/$USERNAME/versions/* 2>/dev/null | sort | tail -1)
if [ -n "$latest_snapshot" ] && [ "$latest_snapshot" != "$snapshot_dir" ]; then
    rsync -a --link-dest="$latest_snapshot" "/home/$USERNAME/uploads/" "$snapshot_dir/"
else
    rsync -a "/home/$USERNAME/uploads/" "$snapshot_dir/"
fi
chown -R root:root "$snapshot_dir" || true
chmod -R 755 "$snapshot_dir" || true

# Log creation to monitor log if it exists
if [ -w /var/log/backup_monitor.log ] || [ -w /var/log ]; then
    echo "$(date '+%F %T') Initial snapshot created for $USERNAME at $timestamp" >> /var/log/backup_monitor.log 2>/dev/null || true
fi

echo "Initial snapshot created: $snapshot_dir"