#!/bin/bash

# delete_user.sh - Delete a backup user and all their data
# Usage: sudo ./delete_user.sh <username>
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/terminas

# Get version from VERSION file in repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../../VERSION"
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    VERSION="unknown"
fi

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1

# Check if user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME does not exist."
    exit 1
fi

# Safety confirmation - require typing username
echo ""
echo "WARNING: This will permanently delete user '$USERNAME' and ALL backup data!"
echo "This action CANNOT be undone."
echo ""
read -p "Type the username '$USERNAME' again to confirm deletion: " confirmation

if [ "$confirmation" != "$USERNAME" ]; then
    echo "Username mismatch. Aborting deletion."
    exit 1
fi

echo ""
echo "Deleting user $USERNAME..."

# Kill any processes owned by the user
pkill -u "$USERNAME" 2>/dev/null || true

# Remove Samba user if exists
if command -v smbpasswd &>/dev/null; then
    if pdbedit -L 2>/dev/null | grep -q "^$USERNAME:"; then
        echo "Removing Samba user..."
        smbpasswd -x "$USERNAME" 2>/dev/null || true
    fi
fi

# Remove Samba configuration file
if [ -f "/etc/samba/smb.conf.d/$USERNAME.conf" ]; then
    echo "Removing Samba configuration..."
    rm -f "/etc/samba/smb.conf.d/$USERNAME.conf"
    
    # Also remove from main smb.conf
    if [ -f /etc/samba/smb.conf ]; then
        # Remove the share section (from comment line to next blank line or EOF)
        sed -i "/^# Share for user: $USERNAME$/,/^$/d" /etc/samba/smb.conf
        # Fallback: remove share block if comment line doesn't exist
        sed -i "/^\[$USERNAME-backup\]$/,/^$/d" /etc/samba/smb.conf
    fi
    
    # Restart Samba to apply changes
    if systemctl is-active --quiet smbd; then
        systemctl restart smbd 2>/dev/null || true
        echo "  Restarted Samba service"
    fi
fi

# Remove the user (without -r since home is owned by root)
userdel "$USERNAME"

# Delete Btrfs subvolumes and directories
if [ -d "/home/$USERNAME" ]; then
    echo "Removing Btrfs subvolumes and data..."
    
    # Delete uploads subvolume
    if [ -d "/home/$USERNAME/uploads" ]; then
        if btrfs subvolume show "/home/$USERNAME/uploads" &>/dev/null; then
            echo "  Deleting uploads subvolume..."
            btrfs subvolume delete "/home/$USERNAME/uploads" >/dev/null 2>&1 || rm -rf "/home/$USERNAME/uploads"
        else
            rm -rf "/home/$USERNAME/uploads"
        fi
    fi
    
    # Delete all snapshot subvolumes in versions/
    if [ -d "/home/$USERNAME/versions" ]; then
        echo "  Deleting snapshot subvolumes..."
        count=0
        for snapshot in /home/$USERNAME/versions/*; do
            if [ -d "$snapshot" ]; then
                if btrfs subvolume show "$snapshot" &>/dev/null; then
                    # Make snapshot writable before deletion
                    btrfs property set -ts "$snapshot" ro false 2>/dev/null || true
                    btrfs subvolume delete "$snapshot" >/dev/null 2>&1 && count=$((count + 1))
                else
                    rm -rf "$snapshot" && count=$((count + 1))
                fi
            fi
        done
        [ $count -gt 0 ] && echo "    Deleted $count snapshots"
        rmdir "/home/$USERNAME/versions" 2>/dev/null || rm -rf "/home/$USERNAME/versions"
    fi
    
    # Remove home directory
    rm -rf "/home/$USERNAME"
fi

# Remove any runtime files
rm -f "/var/run/terminas/last_$USERNAME" 2>/dev/null || true
rm -f "/var/run/terminas/activity_$USERNAME" 2>/dev/null || true
rm -f "/var/run/terminas/snapshot_$USERNAME" 2>/dev/null || true
rm -f "/var/run/terminas/processing_$USERNAME" 2>/dev/null || true

echo "User $USERNAME and all their data have been deleted."