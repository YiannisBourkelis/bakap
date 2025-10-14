#!/bin/bash

# create_user.sh - Create a backup user with secure password and versioning setup
# Usage: ./create_user.sh <username> [-p|--password <password>] [-s|--samba]
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

# Function to setup Samba share with strict security
setup_samba_share() {
    local username="$1"
    local password="$2"
    
    echo "Setting up Samba share for $username..."
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        echo "To enable Samba support, run setup.sh with the --samba option:"
        echo "  ./setup.sh --samba"
        echo "Then re-run this command to create the user with Samba support."
        return 1
    fi
    
    # Enable Samba user with the same password
    echo -e "$password\n$password" | smbpasswd -a "$username" -s
    
    # Create Samba configuration for this user with strict security
    local smb_conf="/etc/samba/smb.conf.d/$username.conf"
    mkdir -p /etc/samba/smb.conf.d
    
    # Create per-user config file for easy maintenance
    cat > "$smb_conf" << EOF
[$username-backup]
   path = /home/$username/uploads
   browseable = no
   writable = yes
   guest ok = no
   valid users = $username
   create mask = 0644
   directory mask = 0755
   force user = $username
   force group = backupusers
   # Strict security settings
   read only = no
   public = no
   printable = no
   store dos attributes = no
   map archive = no
   map hidden = no
   map system = no
   map readonly = no
   # VFS audit module for tracking SMB file operations
   vfs objects = full_audit
   full_audit:prefix = %u|%I|%m
   full_audit:success = connect disconnect open close write pwrite
   full_audit:failure = connect
   full_audit:facility = local1
   full_audit:priority = notice
EOF
    
    # Add explicit include to main smb.conf for this user's config
    # (Per-user config files are loaded via explicit includes, not wildcards)
    if [ -f /etc/samba/smb.conf ] && ! grep -q "^include = $smb_conf" /etc/samba/smb.conf 2>/dev/null; then
        # Find the line with "# Explicit includes for per-user configurations" and add after it
        if grep -q "# Explicit includes for per-user configurations" /etc/samba/smb.conf; then
            # Add after the comment line
            sed -i "/# Explicit includes for per-user configurations/a include = $smb_conf" /etc/samba/smb.conf
        else
            # Fallback: append at end
            echo "include = $smb_conf" >> /etc/samba/smb.conf
        fi
    fi
    
    # Restart Samba services (nmbd may not be running on all systems)
    if systemctl restart smbd nmbd 2>/dev/null; then
        : # Both services restarted successfully
    else
        systemctl restart smbd 2>/dev/null || true
    fi
    
    echo "  ✓ Samba share created: //$HOSTNAME/$username-backup"
    echo "  ✓ Access credentials: $username / [same password as SFTP]"
}

# Parse command line arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <username> [-p|--password <password>] [-s|--samba]"
    echo ""
    echo "Options:"
    echo "  -p, --password  Manually specify password (must be 30+ chars with lowercase, uppercase, and numbers)"
    echo "  -s, --samba     Enable Samba (SMB) sharing for uploads directory"
    echo ""
    echo "If no password is provided, a secure 64-character random password will be generated."
    echo "Samba sharing allows other applications to use the uploads directory as a network share."
    exit 1
fi

USERNAME=$1
PASSWORD=""
ENABLE_SAMBA=false

# Parse optional parameters
shift
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--password)
            if [ -z "${2:-}" ]; then
                echo "ERROR: --password requires a value"
                exit 1
            fi
            PASSWORD="$2"
            shift 2
            ;;
        -s|--samba)
            ENABLE_SAMBA=true
            shift
            ;;
        *)
            echo "ERROR: Unknown parameter: $1"
            echo "Usage: $0 <username> [-p|--password <password>] [-s|--samba]"
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

# Setup Samba share if requested
if [ "$ENABLE_SAMBA" = "true" ]; then
    if ! setup_samba_share "$USERNAME" "$PASSWORD"; then
        echo "Failed to setup Samba share for user $USERNAME."
        echo "Cleaning up..."
        userdel -r "$USERNAME" 2>/dev/null
        exit 1
    fi
    echo "User $USERNAME created successfully with Samba support."
else
    echo "User $USERNAME created successfully."
fi

echo "Upload subvolume: /home/$USERNAME/uploads (Btrfs subvolume)"
echo "Versions directory: /home/$USERNAME/versions (read-only Btrfs snapshots)"
echo "Btrfs snapshots will be created automatically on file uploads via inotify monitoring."