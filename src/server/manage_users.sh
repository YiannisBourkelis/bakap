#!/bin/bash

# manage_users.sh - Manage backup users, view stats, cleanup, and delete users
# Usage: ./manage_users.sh [command] [options]
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details
# https://github.com/YiannisBourkelis/bakap

set -e

SCRIPT_NAME=$(basename "$0")

usage() {
    cat <<EOF
Bakap User Management Tool
Copyright (c) 2025 Yianni Bourkelis
https://github.com/YiannisBourkelis/bakap

Usage: $SCRIPT_NAME <command> [options]

Commands:
    list                    List all backup users with their disk usage
    info <username>         Show detailed information about a specific user
    history <username>      Show snapshot history for a user
    search <pattern>        Search for files in latest snapshots
    inactive [days]         List users with no recent uploads (default: 30 days)
    restore <username> <snapshot> <dest>  Restore files from a snapshot
    delete <username>       Delete a user and all their files
    cleanup <username>      Keep only the latest snapshot (removes old snapshots, keeps actual files)
    cleanup-all             Cleanup all backup users (keep latest snapshot for each)
    help                    Show this help message

Examples:
    $SCRIPT_NAME list
    $SCRIPT_NAME info testuser
    $SCRIPT_NAME history testuser
    $SCRIPT_NAME search "*.pdf"
    $SCRIPT_NAME inactive 60
    $SCRIPT_NAME restore testuser 2025-10-01_14-30-00 /tmp/restore
    $SCRIPT_NAME delete testuser
    $SCRIPT_NAME cleanup testuser
    $SCRIPT_NAME cleanup-all

Notes:
    - The cleanup command preserves actual files by copying the latest snapshot
    - Symlinks/hardlinks in older snapshots are removed
    - Delete command removes the user and ALL their data permanently
    - Restore command copies files to specified destination (destination must not exist)
    - Search looks through latest snapshots only
EOF
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root" >&2
        exit 1
    fi
}

# Get list of backup users (members of backupusers group)
get_backup_users() {
    # Get the GID of backupusers group
    local gid=$(getent group backupusers 2>/dev/null | cut -d: -f3)
    if [ -z "$gid" ]; then
        return
    fi
    
    # Find users with backupusers as primary group (from /etc/passwd)
    # Format: username:x:uid:gid:...
    local primary_users=$(getent passwd | awk -F: -v gid="$gid" '$4 == gid {print $1}')
    
    # Find users with backupusers as supplementary group
    local supp_users=$(getent group backupusers 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^$')
    
    # Combine and deduplicate
    echo -e "${primary_users}\n${supp_users}" | grep -v '^$' | sort -u
}

# Calculate actual disk usage (counting hardlinks only once) in MB with decimals
get_actual_size() {
    local path="$1"
    if [ -d "$path" ]; then
        # Use du in KB and convert to MB with 2 decimal places
        local kb=$(du -sLk "$path" 2>/dev/null | awk '{print $1}')
        echo "scale=2; $kb / 1024" | bc
    else
        echo "0.00"
    fi
}

# Calculate apparent size (what ls -l would show) in MB with decimals
get_apparent_size() {
    local path="$1"
    if [ -d "$path" ]; then
        # Use du in KB and convert to MB with 2 decimal places
        local kb=$(du -sk --apparent-size "$path" 2>/dev/null | awk '{print $1}')
        echo "scale=2; $kb / 1024" | bc
    else
        echo "0.00"
    fi
}

# Get last backup date for a user
get_last_backup_date() {
    local user="$1"
    local home_dir="/home/$user"
    local last_activity=""
    local activity_epoch=0
    
    # Check latest snapshot
    if [ -d "$home_dir/versions" ]; then
        local latest_snapshot=$(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
        if [ -n "$latest_snapshot" ]; then
            activity_epoch=$(stat -c %Y "$latest_snapshot" 2>/dev/null || stat -f %m "$latest_snapshot" 2>/dev/null || echo 0)
        fi
    fi
    
    # Check uploads directory for any newer files
    if [ -d "$home_dir/uploads" ]; then
        local latest_file=$(find "$home_dir/uploads" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
        if [ -n "$latest_file" ]; then
            local file_epoch=$(echo "$latest_file" | cut -d' ' -f1 | cut -d. -f1)
            if [ "$file_epoch" -gt "$activity_epoch" ]; then
                activity_epoch=$file_epoch
            fi
        fi
    fi
    
    if [ "$activity_epoch" -gt 0 ]; then
        last_activity=$(date -d "@$activity_epoch" "+%Y-%m-%d" 2>/dev/null || date -r "$activity_epoch" "+%Y-%m-%d" 2>/dev/null || echo "Unknown")
        echo "$last_activity|$activity_epoch"
    else
        echo "Never|0"
    fi
}

# List all backup users with their disk usage
list_users() {
    echo "Backup Users:"
    echo "==============================================================================="
    printf "%-15s %10s %10s %8s %12s %s\n" "Username" "Size (MB)" "Apparent" "Snaps" "Last Backup" "Status"
    echo "-------------------------------------------------------------------------------"
    
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    local total_actual="0.00"
    local total_apparent="0.00"
    local total_users=0
    local now=$(date +%s)
    local warn_threshold=$((15 * 86400))  # 15 days in seconds
    
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        local home_dir="/home/$user"
        if [ ! -d "$home_dir" ]; then
            continue
        fi
        
        # Calculate sizes
        local actual_size=$(get_actual_size "$home_dir")
        local apparent_size=$(get_apparent_size "$home_dir")
        
        # Count snapshots
        local snapshot_count=0
        if [ -d "$home_dir/versions" ]; then
            snapshot_count=$(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        fi
        
        # Get last backup date
        local backup_info=$(get_last_backup_date "$user")
        local last_date=$(echo "$backup_info" | cut -d'|' -f1)
        local last_epoch=$(echo "$backup_info" | cut -d'|' -f2)
        
        # Determine status
        local status="OK"
        local status_color=""
        if [ "$last_date" = "Never" ]; then
            status="⚠ NEVER"
            status_color="\033[1;33m"  # Yellow
        elif [ "$last_epoch" -gt 0 ]; then
            local days_ago=$(( (now - last_epoch) / 86400 ))
            if [ $days_ago -gt 15 ]; then
                status="⚠ ${days_ago}d ago"
                status_color="\033[1;33m"  # Yellow
            else
                status="✓ ${days_ago}d ago"
                status_color="\033[0;32m"  # Green
            fi
        fi
        
        # Print with color if status needs attention
        if [ -n "$status_color" ] && [ "$status" != "✓"* ]; then
            printf "%-15s %10s %10s %8s %12s ${status_color}%s\033[0m\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$last_date" "$status"
        else
            printf "%-15s %10s %10s %8s %12s %s\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$last_date" "$status"
        fi
        
        # Sum up totals using bc for decimal arithmetic
        total_actual=$(echo "$total_actual + $actual_size" | bc)
        total_apparent=$(echo "$total_apparent + $apparent_size" | bc)
        total_users=$((total_users + 1))
    done <<< "$users"
    
    echo "-------------------------------------------------------------------------------"
    printf "%-15s %10s %10s %8s\n" "Total: $total_users" "$total_actual" "$total_apparent" ""
    echo ""
    echo "Note: Size shows real disk usage (hardlinks counted once)"
    echo "      Status: ✓ = backed up recently, ⚠ = >15 days since last backup"
}

# Show detailed information about a specific user
info_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        usage
        exit 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        exit 1
    fi
    
    local home_dir="/home/$username"
    if [ ! -d "$home_dir" ]; then
        echo "Error: Home directory not found for user '$username'" >&2
        exit 1
    fi
    
    echo "User Information: $username"
    echo "========================================"
    
    # User details
    echo "UID: $(id -u "$username")"
    echo "Groups: $(groups "$username" | cut -d: -f2)"
    echo "Home: $home_dir"
    echo ""
    
    # Disk usage - check if directories have actual files first
    local has_files=0
    if [ -n "$(find "$home_dir/uploads" -type f 2>/dev/null | head -1)" ] || \
       [ -n "$(find "$home_dir/versions" -type f 2>/dev/null | head -1)" ]; then
        has_files=1
    fi
    
    if [ "$has_files" -eq 1 ]; then
        local actual_size=$(get_actual_size "$home_dir")
        local apparent_size=$(get_apparent_size "$home_dir")
        local uploads_size=$(get_actual_size "$home_dir/uploads")
        local versions_size=$(get_actual_size "$home_dir/versions")
        
        # Calculate space saved by hardlinks in versions directory
        local versions_actual=$(get_actual_size "$home_dir/versions")
        local versions_apparent=$(get_apparent_size "$home_dir/versions")
        local space_saved=$(echo "$versions_apparent - $versions_actual" | bc)
        
        echo "Disk Usage:"
        echo "  Total (actual):     ${actual_size} MB"
        echo "  Total (apparent):   ${apparent_size} MB"
        echo "  Uploads:            ${uploads_size} MB"
        echo "  Versions (actual):  ${versions_actual} MB"
        echo "  Versions (apparent): ${versions_apparent} MB"
        echo "  Space saved:        ${space_saved} MB (via hardlinks)"
    else
        echo "Disk Usage:"
        echo "  No files uploaded yet (0.00 MB)"
    fi
    echo ""
    
    # Snapshot statistics
    local versions_dir="$home_dir/versions"
    if [ -d "$versions_dir" ]; then
        local snapshot_count=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        echo "Snapshots: $snapshot_count"
        
        if [ "$snapshot_count" -gt 0 ]; then
            local oldest=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)
            local newest=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
            
            if [ -n "$oldest" ]; then
                echo "  Oldest:  $(basename "$oldest")"
                local oldest_date=$(stat -c %y "$oldest" 2>/dev/null | cut -d. -f1 || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$oldest" 2>/dev/null)
                echo "           Created: $oldest_date"
            fi
            
            if [ -n "$newest" ]; then
                echo "  Newest:  $(basename "$newest")"
                local newest_date=$(stat -c %y "$newest" 2>/dev/null | cut -d. -f1 || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$newest" 2>/dev/null)
                echo "           Created: $newest_date"
            fi
        fi
    else
        echo "Snapshots: 0"
    fi
    echo ""
    
    # Upload activity
    if [ -d "$home_dir/uploads" ]; then
        local file_count=$(find "$home_dir/uploads" -type f 2>/dev/null | wc -l)
        echo "Current uploads: $file_count files"
        
        if [ "$file_count" -gt 0 ]; then
            local latest_file=$(find "$home_dir/uploads" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            if [ -n "$latest_file" ]; then
                local latest_date=$(stat -c %y "$latest_file" 2>/dev/null | cut -d. -f1 || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$latest_file" 2>/dev/null)
                echo "  Last upload: $latest_date"
            fi
        fi
    else
        echo "Current uploads: 0 files"
    fi
    echo ""
    
    # Retention policy (if custom)
    if [ -f /etc/bakap-retention.conf ]; then
        source /etc/bakap-retention.conf
        local has_custom=false
        
        local user_daily_var="${username}_KEEP_DAILY"
        local user_weekly_var="${username}_KEEP_WEEKLY"
        local user_monthly_var="${username}_KEEP_MONTHLY"
        local user_retention_var="${username}_RETENTION_DAYS"
        local user_advanced_var="${username}_ENABLE_ADVANCED_RETENTION"
        
        if [ -n "${!user_daily_var}" ] || [ -n "${!user_weekly_var}" ] || [ -n "${!user_monthly_var}" ] || \
           [ -n "${!user_retention_var}" ] || [ -n "${!user_advanced_var}" ]; then
            has_custom=true
        fi
        
        if [ "$has_custom" = true ]; then
            echo "Retention Policy: Custom"
            [ -n "${!user_advanced_var}" ] && echo "  Advanced: ${!user_advanced_var}"
            [ -n "${!user_daily_var}" ] && echo "  Keep daily: ${!user_daily_var}"
            [ -n "${!user_weekly_var}" ] && echo "  Keep weekly: ${!user_weekly_var}"
            [ -n "${!user_monthly_var}" ] && echo "  Keep monthly: ${!user_monthly_var}"
            [ -n "${!user_retention_var}" ] && echo "  Retention days: ${!user_retention_var}"
        else
            echo "Retention Policy: Default (from /etc/bakap-retention.conf)"
        fi
    fi
}

# Show snapshot history for a user
history_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        usage
        exit 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        exit 1
    fi
    
    local versions_dir="/home/$username/versions"
    
    if [ ! -d "$versions_dir" ]; then
        echo "No versions directory found for user '$username'"
        return
    fi
    
    local snapshots=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
    local snapshot_count=$(echo "$snapshots" | grep -v '^$' | wc -l)
    
    if [ "$snapshot_count" -eq 0 ]; then
        echo "No snapshots found for user '$username'"
        return
    fi
    
    echo "Snapshot History for: $username"
    echo "========================================"
    printf "%-25s %15s %10s\n" "Snapshot" "Size (MB)" "Files"
    echo "----------------------------------------"
    
    while IFS= read -r snapshot; do
        if [ -z "$snapshot" ] || [ ! -d "$snapshot" ]; then
            continue
        fi
        
        local name=$(basename "$snapshot")
        local size=$(get_actual_size "$snapshot")
        local file_count=$(find "$snapshot" -type f 2>/dev/null | wc -l)
        
        printf "%-25s %15s %10s\n" "$name" "$size" "$file_count"
    done <<< "$snapshots"
    
    echo "----------------------------------------"
    echo "Total snapshots: $snapshot_count"
}

# Search for files across all users' latest snapshots
search_files() {
    local pattern="$1"
    
    if [ -z "$pattern" ]; then
        echo "Error: Search pattern is required" >&2
        usage
        exit 1
    fi
    
    echo "Searching for: $pattern"
    echo "========================================"
    
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    local found=0
    
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        local versions_dir="/home/$user/versions"
        if [ ! -d "$versions_dir" ]; then
            continue
        fi
        
        # Get latest snapshot
        local latest_snapshot=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
        if [ -z "$latest_snapshot" ]; then
            continue
        fi
        
        # Search in latest snapshot
        local results=$(find "$latest_snapshot" -type f -name "$pattern" 2>/dev/null)
        
        if [ -n "$results" ]; then
            echo ""
            echo "User: $user ($(basename "$latest_snapshot"))"
            echo "----------------------------------------"
            while IFS= read -r file; do
                if [ -n "$file" ]; then
                    local size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
                    local rel_path=${file#$latest_snapshot/}
                    printf "  %s (%s bytes)\n" "$rel_path" "$size"
                    found=$((found + 1))
                fi
            done <<< "$results"
        fi
    done <<< "$users"
    
    echo ""
    echo "========================================"
    echo "Found $found matching files"
}

# List inactive users (no recent uploads)
list_inactive() {
    local days="${1:-30}"
    
    echo "Users with no uploads in last $days days:"
    echo "========================================"
    printf "%-20s %25s %15s\n" "Username" "Last Activity" "Snapshots"
    echo "----------------------------------------"
    
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    local now=$(date +%s)
    local cutoff=$((now - days * 86400))
    local inactive_count=0
    
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        local home_dir="/home/$user"
        if [ ! -d "$home_dir/uploads" ]; then
            continue
        fi
        
        # Find most recent file modification in uploads
        local latest_file=$(find "$home_dir/uploads" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
        
        if [ -z "$latest_file" ]; then
            # No files in uploads - check versions
            local versions_dir="$home_dir/versions"
            if [ -d "$versions_dir" ]; then
                local latest_snapshot=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
                if [ -n "$latest_snapshot" ]; then
                    local snapshot_time=$(stat -c %Y "$latest_snapshot" 2>/dev/null || stat -f %m "$latest_snapshot" 2>/dev/null)
                    if [ "$snapshot_time" -lt "$cutoff" ]; then
                        local last_activity=$(date -d "@$snapshot_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$snapshot_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
                        local snapshot_count=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
                        printf "%-20s %25s %15s\n" "$user" "$last_activity" "$snapshot_count"
                        inactive_count=$((inactive_count + 1))
                    fi
                else
                    printf "%-20s %25s %15s\n" "$user" "Never" "0"
                    inactive_count=$((inactive_count + 1))
                fi
            else
                printf "%-20s %25s %15s\n" "$user" "Never" "0"
                inactive_count=$((inactive_count + 1))
            fi
        else
            local file_time=$(echo "$latest_file" | cut -d' ' -f1 | cut -d. -f1)
            if [ "$file_time" -lt "$cutoff" ]; then
                local last_activity=$(date -d "@$file_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$file_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
                local snapshot_count=0
                if [ -d "$home_dir/versions" ]; then
                    snapshot_count=$(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
                fi
                printf "%-20s %25s %15s\n" "$user" "$last_activity" "$snapshot_count"
                inactive_count=$((inactive_count + 1))
            fi
        fi
    done <<< "$users"
    
    echo "----------------------------------------"
    echo "Total inactive users: $inactive_count"
}

# Restore files from a snapshot
restore_snapshot() {
    local username="$1"
    local snapshot_name="$2"
    local dest_path="$3"
    
    if [ -z "$username" ] || [ -z "$snapshot_name" ] || [ -z "$dest_path" ]; then
        echo "Error: Username, snapshot name, and destination path are required" >&2
        usage
        exit 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        exit 1
    fi
    
    local snapshot_dir="/home/$username/versions/$snapshot_name"
    
    if [ ! -d "$snapshot_dir" ]; then
        echo "Error: Snapshot '$snapshot_name' not found for user '$username'" >&2
        echo ""
        echo "Available snapshots:"
        find "/home/$username/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | xargs -n1 basename
        exit 1
    fi
    
    # Check if destination exists
    if [ -e "$dest_path" ]; then
        echo "Error: Destination '$dest_path' already exists" >&2
        echo "Please choose a different destination or remove the existing path" >&2
        exit 1
    fi
    
    echo "Restoring snapshot '$snapshot_name' for user '$username'..."
    echo "Source: $snapshot_dir"
    echo "Destination: $dest_path"
    echo ""
    
    # Create destination directory
    mkdir -p "$dest_path"
    
    # Copy files
    echo "Copying files..."
    rsync -av --progress "$snapshot_dir/" "$dest_path/" 2>&1 | tail -20
    
    if [ $? -eq 0 ]; then
        local file_count=$(find "$dest_path" -type f 2>/dev/null | wc -l)
        local total_size=$(du -sh "$dest_path" 2>/dev/null | cut -f1)
        echo ""
        echo "Restore completed successfully!"
        echo "Files restored: $file_count"
        echo "Total size: $total_size"
        echo "Location: $dest_path"
    else
        echo "Error: Restore failed" >&2
        exit 1
    fi
}

# Delete a user and all their files
delete_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        usage
        exit 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        exit 1
    fi
    
    # Check if user is in backupusers group
    if ! groups "$username" | grep -q backupusers; then
        echo "Error: User '$username' is not a backup user" >&2
        exit 1
    fi
    
    # Confirm deletion
    echo "WARNING: This will permanently delete user '$username' and ALL their data!"
    echo "This includes:"
    echo "  - User account"
    echo "  - /home/$username/uploads/"
    echo "  - /home/$username/versions/ (all snapshots)"
    echo ""
    read -p "Are you sure? Type 'yes' to confirm: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Deletion cancelled."
        exit 0
    fi
    
    echo "Deleting user '$username'..."
    
    # Delete user
    userdel "$username" 2>/dev/null || true
    
    # Remove home directory and all files
    if [ -d "/home/$username" ]; then
        echo "Removing /home/$username..."
        rm -rf "/home/$username"
    fi
    
    # Remove any runtime files
    rm -f "/var/run/bakap/last_$username" 2>/dev/null || true
    
    echo "User '$username' and all their data have been deleted."
}

# Cleanup user: keep only latest snapshot with actual files
cleanup_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        usage
        exit 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        exit 1
    fi
    
    local home_dir="/home/$username"
    local versions_dir="$home_dir/versions"
    
    if [ ! -d "$versions_dir" ]; then
        echo "No versions directory found for user '$username'"
        return
    fi
    
    # Find all snapshots
    local snapshots=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    local snapshot_count=$(echo "$snapshots" | grep -v '^$' | wc -l)
    
    if [ "$snapshot_count" -eq 0 ]; then
        echo "No snapshots found for user '$username'"
        return
    fi
    
    if [ "$snapshot_count" -eq 1 ]; then
        echo "User '$username' has only one snapshot. Nothing to cleanup."
        return
    fi
    
    # Get latest snapshot
    local latest_snapshot=$(echo "$snapshots" | tail -1)
    local latest_name=$(basename "$latest_snapshot")
    
    echo "User: $username"
    echo "Total snapshots: $snapshot_count"
    echo "Latest snapshot: $latest_name"
    echo "Keeping latest snapshot and removing $((snapshot_count - 1)) older snapshot(s)..."
    
    # Calculate space before cleanup
    local size_before=$(get_actual_size "$versions_dir")
    
    # Create a temporary directory for the new snapshot with actual files
    local temp_snapshot="${versions_dir}/.cleanup_${latest_name}"
    
    echo "Copying actual files from latest snapshot..."
    mkdir -p "$temp_snapshot"
    
    # Copy files, following symlinks to copy actual data
    rsync -aL "$latest_snapshot/" "$temp_snapshot/" 2>/dev/null || {
        echo "Error: Failed to copy snapshot data" >&2
        rm -rf "$temp_snapshot"
        exit 1
    }
    
    # Remove all old snapshots
    echo "Removing old snapshots..."
    while IFS= read -r snapshot; do
        if [ -n "$snapshot" ] && [ -d "$snapshot" ]; then
            rm -rf "$snapshot"
        fi
    done <<< "$snapshots"
    
    # Rename temp snapshot to latest
    mv "$temp_snapshot" "$latest_snapshot"
    
    # Set proper permissions
    chown -R root:root "$latest_snapshot"
    chmod -R 755 "$latest_snapshot"
    
    # Calculate space after cleanup
    local size_after=$(get_actual_size "$versions_dir")
    local space_freed=$(echo "$size_before - $size_after" | bc)
    
    echo "Cleanup complete for user '$username'"
    echo "Space before: ${size_before} MB"
    echo "Space after: ${size_after} MB"
    echo "Space freed: ${space_freed} MB"
    echo "Latest snapshot preserved: $latest_name"
}

# Cleanup all backup users
cleanup_all() {
    echo "Cleaning up all backup users..."
    echo ""
    
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    local cleaned=0
    local skipped=0
    
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        echo "----------------------------------------"
        cleanup_user "$user"
        cleaned=$((cleaned + 1))
        echo ""
    done <<< "$users"
    
    echo "========================================"
    echo "Cleanup summary:"
    echo "  Users processed: $cleaned"
    echo "========================================"
}

# Main script logic
check_root

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    list|ls)
        list_users
        ;;
    info|show)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for info command" >&2
            usage
            exit 1
        fi
        info_user "$1"
        ;;
    history|hist)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for history command" >&2
            usage
            exit 1
        fi
        history_user "$1"
        ;;
    search|find)
        if [ $# -eq 0 ]; then
            echo "Error: Search pattern is required for search command" >&2
            usage
            exit 1
        fi
        search_files "$1"
        ;;
    inactive)
        list_inactive "$1"
        ;;
    restore)
        if [ $# -lt 3 ]; then
            echo "Error: Username, snapshot name, and destination are required for restore command" >&2
            usage
            exit 1
        fi
        restore_snapshot "$1" "$2" "$3"
        ;;
    delete|remove|del)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for delete command" >&2
            usage
            exit 1
        fi
        delete_user "$1"
        ;;
    cleanup)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for cleanup command" >&2
            usage
            exit 1
        fi
        cleanup_user "$1"
        ;;
    cleanup-all)
        cleanup_all
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Error: Unknown command '$command'" >&2
        echo ""
        usage
        exit 1
        ;;
esac
