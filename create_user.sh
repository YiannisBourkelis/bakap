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

# Set ownership for chroot (home must be root-owned)
chown root:root "/home/$USERNAME"

# Create directories
mkdir -p "/home/$USERNAME/uploads"
mkdir -p "/home/$USERNAME/versions"

# Set permissions
chown "$USERNAME:backupusers" "/home/$USERNAME/uploads"
chmod 755 "/home/$USERNAME/uploads"
chown root:root "/home/$USERNAME/versions"
chmod 755 "/home/$USERNAME/versions"

echo "User $USERNAME created successfully."
echo "Upload directory: /home/$USERNAME/uploads"
echo "Versions directory: /home/$USERNAME/versions (read-only for user)"
echo "Password: $PASSWORD"
echo "Snapshots are created in real-time on file changes."