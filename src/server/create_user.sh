#!/bin/bash

# create_user.sh - Create a backup user with secure password and versioning setup
# Usage: ./create_user.sh <username> [-p|--password <password>]
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/bakap

set -e

# Function to validate password strength
validate_password() {
    local password="$1"
    local length=${#password}
    
    # Check minimum length (30 characters)
    if [ "$length" -lt 30 ]; then
        echo "ERROR: Password must be at least 30 characters long (provided: $length characters)"
        return 1
    fi
    
    # Check for lowercase letters
    if ! echo "$password" | grep -q '[a-z]'; then
        echo "ERROR: Password must contain at least one lowercase letter"
        return 1
    fi
    
    # Check for uppercase letters
    if ! echo "$password" | grep -q '[A-Z]'; then
        echo "ERROR: Password must contain at least one uppercase letter"
        return 1
    fi
    
    # Check for numbers
    if ! echo "$password" | grep -q '[0-9]'; then
        echo "ERROR: Password must contain at least one number"
        return 1
    fi
    
    return 0
}

# Parse command line arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <username> [-p|--password <password>]"
    echo ""
    echo "Options:"
    echo "  -p, --password  Manually specify password (must be 30+ chars with lowercase, uppercase, and numbers)"
    echo ""
    echo "If no password is provided, a secure 64-character random password will be generated."
    exit 1
fi

USERNAME=$1
PASSWORD=""

# Parse optional password parameter
shift
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--password)
            if [ -z "$2" ]; then
                echo "ERROR: --password requires a value"
                exit 1
            fi
            PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown parameter: $1"
            echo "Usage: $0 <username> [-p|--password <password>]"
            exit 1
            ;;
    esac
done

# Check if user exists
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists."
    exit 1
fi

# Generate or validate password
if [ -z "$PASSWORD" ]; then
    # Generate secure password
    PASSWORD=$(pwgen -s 64 1)
    echo "Generated secure password: $PASSWORD"
else
    # Validate manually provided password
    if ! validate_password "$PASSWORD"; then
        exit 1
    fi
    echo "Using provided password (validated: 30+ chars, lowercase, uppercase, numbers)"
fi

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

# Create Btrfs subvolume for uploads (instead of regular directory)
echo "Creating Btrfs subvolume for uploads..."
if btrfs subvolume create "/home/$USERNAME/uploads" >/dev/null; then
    echo "  ✓ Created uploads subvolume"
else
    echo "  ERROR: Failed to create Btrfs subvolume"
    echo "  Make sure /home is on a Btrfs filesystem"
    userdel -r "$USERNAME" 2>/dev/null
    exit 1
fi

# Create versions directory (regular directory, will contain snapshots)
mkdir -p "/home/$USERNAME/versions"

# Set permissions
# uploads subvolume should be writable only by the user
chown "$USERNAME:backupusers" "/home/$USERNAME/uploads"
chmod 700 "/home/$USERNAME/uploads"
# versions are root-owned and not writable by the user
chown root:backupusers "/home/$USERNAME/versions"
chmod 755 "/home/$USERNAME/versions"

echo "User $USERNAME created successfully."
echo "Upload subvolume: /home/$USERNAME/uploads (Btrfs subvolume)"
echo "Versions directory: /home/$USERNAME/versions (read-only Btrfs snapshots)"
echo "Btrfs snapshots will be created automatically on file uploads via inotify monitoring."