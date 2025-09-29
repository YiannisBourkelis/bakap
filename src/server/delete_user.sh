#!/bin/bash

# delete_user.sh - Delete a backup user and all their data
# Usage: sudo ./delete_user.sh <username>

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

# Confirm deletion
read -p "Are you sure you want to delete user $USERNAME and all their data? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deletion cancelled."
    exit 0
fi

echo "Deleting user $USERNAME..."

# Kill any processes owned by the user
pkill -u "$USERNAME" 2>/dev/null || true

# Remove the user (without -r since home is owned by root)
userdel "$USERNAME"

# Manually remove the home directory and all data
if [ -d "/home/$USERNAME" ]; then
    rm -rf "/home/$USERNAME"
fi

echo "User $USERNAME and all their data have been deleted."