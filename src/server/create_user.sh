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

# Set the user's password securely. Prefer creating a SHA-512 hash and applying it with usermod -p.
# Check that python3 exists and provides the 'crypt' module. If not, fall back to openssl,
# and as a last resort use chpasswd (note: chpasswd will break if the password contains ':').
if command -v python3 >/dev/null 2>&1 && python3 -c "import crypt" >/dev/null 2>&1; then
    HASH=$(python3 - <<'PY'
import crypt,sys
pw=sys.stdin.read().rstrip('\n')
print(crypt.crypt(pw, crypt.mksalt(crypt.METHOD_SHA512)))
PY
    ) <<<"$PASSWORD"
    usermod -p "$HASH" "$USERNAME"
elif command -v openssl >/dev/null 2>&1; then
    # Fallback: openssl passwd -6
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
echo "Snapshots will be created automatically on file uploads via inotify monitoring."