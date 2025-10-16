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
    list                    List all backup users with disk usage and connection status
    info <username>         Show detailed information including connection activity
    history <username>      Show snapshot history for a user
    search <pattern>        Search for files in latest snapshots
    inactive [days]         List users with no recent uploads (default: 30 days)
    restore <username> <snapshot> <dest>  Restore files from a snapshot
    delete <username>       Delete a user and all their files
    cleanup <username>      Keep only the latest snapshot (removes old snapshots, keeps actual files)
    cleanup-all             Cleanup all backup users (keep latest snapshot for each)
    rebuild <username>      Delete all snapshots and create fresh snapshot from uploads
    rebuild-all             Rebuild snapshots for all users (skips users with open files)
    enable-samba <username> Enable Samba (SMB) sharing for an existing user
    disable-samba <username> Disable Samba (SMB) sharing for an existing user
    enable-samba-versions <username>  Enable read-only SMB access to versions (snapshots) directory
    disable-samba-versions <username> Disable SMB access to versions directory
    enable-timemachine <username>     Enable macOS Time Machine support for a user
    disable-timemachine <username>    Disable macOS Time Machine support for a user
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
    $SCRIPT_NAME rebuild testuser
    $SCRIPT_NAME rebuild-all
    $SCRIPT_NAME enable-samba testuser
    $SCRIPT_NAME enable-samba-versions testuser
    $SCRIPT_NAME disable-samba-versions testuser
    $SCRIPT_NAME disable-samba testuser
    $SCRIPT_NAME enable-timemachine testuser
    $SCRIPT_NAME disable-timemachine testuser

Notes:
    - The cleanup command removes old Btrfs snapshots and keeps only the latest
    - Delete command removes the user and ALL their data permanently
    - Restore command copies files to specified destination (destination must not exist)
    - Search looks through latest snapshots only
    - Rebuild command deletes ALL existing snapshots and creates fresh snapshot from uploads
    - Rebuild skips users with files open in uploads directory (warns and continues)
    - Rebuild verifies file integrity between uploads and created snapshot
    - Protocol column shows available access methods:
      * SFTP: Basic SFTP-only access
      * SMB+SFTP: Samba share enabled
      * SMB*+SFTP: Samba share + read-only versions access
      * SMBTM+SFTP: Samba share + Time Machine support
      * SMB*TM+SFTP: Samba share + versions + Time Machine
EOF
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root" >&2
        exit 1
    fi
}

# Update Samba configuration to use explicit includes for per-user config files
# This ensures all shares in per-user files are loaded (wildcards don't work with multiple shares)
update_samba_includes() {
    local smb_conf="/etc/samba/smb.conf"
    
    # Check if Samba is configured
    if [ ! -f "$smb_conf" ]; then
        return 0  # Samba not configured, skip
    fi
    
    # Check if smb.conf.d directory exists
    if [ ! -d "/etc/samba/smb.conf.d" ]; then
        return 0
    fi
    
    # Remove any existing include lines (both wildcard and explicit)
    sed -i '/^include = \/etc\/samba\/smb.conf.d\//d' "$smb_conf"
    sed -i '/^config include = \/etc\/samba\/smb.conf.d\//d' "$smb_conf"
    # Also remove the comment line if it exists
    sed -i '/^# Explicit includes for per-user configurations/d' "$smb_conf"
    
    # Find where to insert the includes
    local first_share_line=$(grep -n '^\[.*-backup\]' "$smb_conf" | head -1 | cut -d: -f1)
    
    if [ -n "$first_share_line" ]; then
        # Create a temporary file with the includes
        local tmpfile=$(mktemp)
        echo "# Explicit includes for per-user configurations" > "$tmpfile"
        for conf in /etc/samba/smb.conf.d/*.conf; do
            if [ -f "$conf" ]; then
                echo "include = $conf" >> "$tmpfile"
            fi
        done
        echo "" >> "$tmpfile"
        
        # Split the file and insert includes
        head -n $((first_share_line - 1)) "$smb_conf" > "${smb_conf}.tmp"
        cat "$tmpfile" >> "${smb_conf}.tmp"
        tail -n +${first_share_line} "$smb_conf" >> "${smb_conf}.tmp"
        mv "${smb_conf}.tmp" "$smb_conf"
        rm -f "$tmpfile"
    else
        # No shares yet, append at end of file
        echo "" >> "$smb_conf"
        echo "# Explicit includes for per-user configurations" >> "$smb_conf"
        for conf in /etc/samba/smb.conf.d/*.conf; do
            if [ -f "$conf" ]; then
                echo "include = $conf" >> "$smb_conf"
            fi
        done
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

# Calculate apparent size (sum of all file sizes, counting hardlinks multiple times) in MB with decimals
get_apparent_size() {
    local path="$1"
    if [ -d "$path" ]; then
        # Sum all file sizes using stat and convert directly to MB with awk (avoids bc syntax errors)
        local mb=$(find "$path" -type f -exec stat -c %s {} \; 2>/dev/null | awk '{sum+=$1} END {printf "%.2f", sum/1024/1024}')
        if [ -z "$mb" ] || [ "$mb" = "0.00" ]; then
            echo "0.00"
        else
            echo "$mb"
        fi
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
    
    # Check latest snapshot directory (not files in uploads)
    # This shows when the most recent snapshot was created
    # Sort by modification time (creation time), not alphabetically
    # This handles snapshots with non-standard names like test_manual_*
    if [ -d "$home_dir/versions" ]; then
        local latest_snapshot=$(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        if [ -n "$latest_snapshot" ]; then
            activity_epoch=$(stat -c %Y "$latest_snapshot" 2>/dev/null || stat -f %m "$latest_snapshot" 2>/dev/null || echo 0)
        fi
    fi
    
    if [ "$activity_epoch" -gt 0 ]; then
        last_activity=$(date -d "@$activity_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$activity_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
        echo "$last_activity|$activity_epoch"
    else
        echo "Never|0"
    fi
}

# Build a dictionary of all user last connections (called once for performance)
# Returns associative array: username -> "formatted_date|epoch"
build_connection_cache() {
    declare -gA CONNECTION_CACHE
    
    # Try systemd journal first (Debian 12+)
    if command -v journalctl &>/dev/null; then
        # Get all accepted authentications in last 90 days, extract username and timestamp
        while IFS= read -r line; do
            # Extract username from "Accepted password for USERNAME" or "Accepted publickey for USERNAME"
            local user=$(echo "$line" | sed -n 's/.*Accepted \(password\|publickey\) for \([^ ]*\).*/\2/p' | head -1)
            if [ -n "$user" ]; then
                # Extract timestamp (first 3 fields: Oct 10 08:15:30)
                local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
                local epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo 0)
                
                if [ "$epoch" -gt 0 ]; then
                    # Only store if this is newer than what we have (or first entry)
                    if [ -z "${CONNECTION_CACHE[$user]}" ]; then
                        local formatted=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
                        CONNECTION_CACHE[$user]="$formatted|$epoch"
                    else
                        local existing_epoch=$(echo "${CONNECTION_CACHE[$user]}" | cut -d'|' -f2)
                        if [ "$epoch" -gt "$existing_epoch" ]; then
                            local formatted=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
                            CONNECTION_CACHE[$user]="$formatted|$epoch"
                        fi
                    fi
                fi
            fi
        done < <(journalctl -u ssh.service --since "90 days ago" 2>/dev/null | grep -i "Accepted password for\|Accepted publickey for")
        return
    fi
    
    # Fallback to auth.log if available
    if [ -f /var/log/auth.log ]; then
        while IFS= read -r line; do
            local user=$(echo "$line" | sed -n 's/.*Accepted \(password\|publickey\) for \([^ ]*\).*/\2/p' | head -1)
            if [ -n "$user" ]; then
                local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
                local epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo 0)
                
                if [ "$epoch" -gt 0 ]; then
                    if [ -z "${CONNECTION_CACHE[$user]}" ]; then
                        local formatted=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
                        CONNECTION_CACHE[$user]="$formatted|$epoch"
                    else
                        local existing_epoch=$(echo "${CONNECTION_CACHE[$user]}" | cut -d'|' -f2)
                        if [ "$epoch" -gt "$existing_epoch" ]; then
                            local formatted=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
                            CONNECTION_CACHE[$user]="$formatted|$epoch"
                        fi
                    fi
                fi
            fi
        done < <(grep -i "Accepted password for\|Accepted publickey for" /var/log/auth.log 2>/dev/null)
    fi
}

# Get last connection time for a user from cache
get_last_connection() {
    local user="$1"
    
    # Return from cache if available
    if [ -n "${CONNECTION_CACHE[$user]}" ]; then
        echo "${CONNECTION_CACHE[$user]}"
    else
        echo "Never|0"
    fi
}

# Build Samba connection cache
build_samba_connection_cache() {
    declare -gA SAMBA_CONNECTION_CACHE
    
    # Check Samba VFS audit log for SMB file operations
    # The audit log format is: timestamp hostname username|ip|machine|operation
    # Example: Oct 12 14:23:45 debmain sambatest|192.168.1.100|myrsini-pc|connect
    
    local audit_log="/var/log/samba/audit.log"
    local use_journald=false
    
    # Prefer journald if audit.log doesn't exist or is empty
    if [ ! -s "$audit_log" ] && command -v journalctl &>/dev/null; then
        # File doesn't exist or is empty, use journald
        use_journald=true
    elif [ ! -s "$audit_log" ]; then
        # No audit source available (no file and no journalctl)
        return
    fi
    
    local users=$(get_backup_users)
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        # Only check users with Samba enabled
        if ! has_samba_enabled "$user"; then
            continue
        fi
        
        local latest_line=""
        
        if [ "$use_journald" = true ]; then
            # Parse from journald (smbd logs with audit prefix)
            # Format: Oct 12 01:21:40 debmain smbd_audit[536369]: sambatest|94.69.215.1|myrsini-pc|close|ok|...
            # Use SYSLOG_IDENTIFIER=smbd_audit to get VFS audit logs
            latest_line=$(journalctl --since "30 days ago" SYSLOG_IDENTIFIER=smbd_audit --no-pager 2>/dev/null | \
                grep ": $user|" | \
                grep -E "connect|write|pwrite|close" | \
                tail -1)
        else
            # Parse from audit.log file
            # Look for connect, write, pwrite operations (indicates active usage)
            latest_line=$(grep "^[A-Za-z].*$user|" "$audit_log" 2>/dev/null | \
                grep -E "connect|write|pwrite|close" | \
                tail -1)
        fi
        
        if [ -n "$latest_line" ]; then
            # Extract timestamp
            # Journald format: "Oct 12 01:21:40 hostname smbd_audit[...]: ..."
            # We need: "Oct 12 01:21:40" (first 3 fields, but field 3 is the time)
            local month=$(echo "$latest_line" | awk '{print $1}')
            local day=$(echo "$latest_line" | awk '{print $2}')
            local time=$(echo "$latest_line" | awk '{print $3}')
            local timestamp="$month $day $time"
            
            if [ -n "$timestamp" ]; then
                # Convert to epoch - GNU date format
                # Format should be: "2025-10-12 01:24:03" or "Oct 12 01:24:03 2025"
                local current_year=$(date +%Y)
                local epoch=$(date -d "$timestamp $current_year" +%s 2>/dev/null || echo 0)
                
                if [ "$epoch" -gt 0 ]; then
                    local formatted=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
                    SAMBA_CONNECTION_CACHE[$user]="$formatted|$epoch"
                fi
            fi
        fi
    done <<< "$users"
}

# Get last Samba connection time for a user from cache
get_last_samba_connection() {
    local user="$1"
    
    # Return from cache if available
    if [ -n "${SAMBA_CONNECTION_CACHE[$user]}" ]; then
        echo "${SAMBA_CONNECTION_CACHE[$user]}"
    else
        echo "Never|0"
    fi
}

# Check if Samba is enabled for a user
has_samba_enabled() {
    local username="$1"
    # Check if Samba config file exists for this user
    [ -f "/etc/samba/smb.conf.d/${username}.conf" ]
}

# Check if read-only Samba access to versions is enabled for a user
has_samba_versions_enabled() {
    local username="$1"
    # Check if versions share exists in the user's main Samba config file
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    [ -f "$smb_conf" ] && grep -qF "[${username}-versions]" "$smb_conf" 2>/dev/null
}

# Check if Time Machine support is enabled for a user
has_timemachine_enabled() {
    local username="$1"
    # Check if timemachine share exists in the user's main Samba config file
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    [ -f "$smb_conf" ] && grep -qF "[${username}-timemachine]" "$smb_conf" 2>/dev/null
}

# Enable Samba sharing for an existing user
enable_samba() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if user is in backupusers group
    if ! id "$username" | grep -q "backupusers"; then
        echo "Error: User '$username' is not a backup user" >&2
        return 1
    fi
    
    # Check if Samba is already enabled
    if has_samba_enabled "$username"; then
        echo "Samba sharing is already enabled for user '$username'"
        return 0
    fi
    
    echo "Enabling Samba sharing for user '$username'..."
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        echo "To enable Samba support, run setup.sh with the --samba option:"
        echo "  ./setup.sh --samba"
        return 1
    fi
    
    # Check if Samba user already exists
    if pdbedit -L | grep -q "^$username:"; then
        echo "Samba user account already exists for '$username'"
    else
        # Get user's password from /etc/shadow (we need to extract it)
        local shadow_entry=$(getent shadow "$username")
        if [ -z "$shadow_entry" ]; then
            echo "ERROR: Cannot retrieve password for user '$username'" >&2
            return 1
        fi
        
        # For Samba, we need the plain text password. Since we don't have it stored,
        # we'll need to prompt the user to provide it
        echo "Samba requires the user's password to set up the share."
        echo "Please enter the password for user '$username':"
        local password
        read -s -p "Password: " password
        echo ""
        
        if [ -z "$password" ]; then
            echo "ERROR: Password cannot be empty" >&2
            return 1
        fi
        
        # Enable Samba user with the provided password
        echo -e "$password\n$password" | smbpasswd -a "$username" -s
    fi
    
    # Create Samba configuration for this user with strict security
    local smb_conf="/etc/samba/smb.conf.d/$username.conf"
    mkdir -p /etc/samba/smb.conf.d
    
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
   full_audit:success = connect disconnect open close write pwrite mkdir rmdir rename unlink
   full_audit:failure = none
   full_audit:facility = local5
   full_audit:priority = notice
EOF
    
    # Update main smb.conf to include this user's config file
    update_samba_includes
    
    # Restart Samba services
    systemctl restart smbd nmbd
    
    echo "✓ Samba sharing enabled for user '$username'"
    echo "  Share name: //$HOSTNAME/$username-backup"
    echo "  Access credentials: $username / [provided password]"
}

# Disable Samba sharing for an existing user
disable_samba() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if Samba is enabled
    if ! has_samba_enabled "$username"; then
        echo "Samba sharing is not enabled for user '$username'"
        return 0
    fi
    
    echo "Disabling Samba sharing for user '$username'..."
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        return 1
    fi
    
    # Remove Samba user account
    smbpasswd -x "$username" 2>/dev/null || true
    
    # Remove Samba configuration file
    local smb_conf="/etc/samba/smb.conf.d/$username.conf"
    if [ -f "$smb_conf" ]; then
        rm -f "$smb_conf"
        echo "  Removed Samba configuration file"
    fi
    
    # Update main smb.conf to remove this user's include
    update_samba_includes
    
    # Restart Samba services
    systemctl restart smbd nmbd
    
    echo "✓ Samba sharing disabled for user '$username'"
}

# Enable read-only Samba access to versions (snapshots) directory
enable_samba_versions() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if user is in backupusers group
    if ! id "$username" | grep -q "backupusers"; then
        echo "Error: User '$username' is not a backup user" >&2
        return 1
    fi
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        echo "To enable Samba support, run setup.sh with the --samba option:"
        echo "  ./setup.sh --samba"
        return 1
    fi
    
    # Check if Samba user account exists
    if ! pdbedit -L | grep -q "^$username:"; then
        echo "ERROR: User '$username' does not have a Samba account."
        echo "Please run: $SCRIPT_NAME enable-samba $username"
        return 1
    fi
    
    # Check if versions directory exists
    if [ ! -d "/home/$username/versions" ]; then
        echo "ERROR: Versions directory does not exist for user '$username'"
        return 1
    fi
    
    # Check if already enabled (check in the user's main config file)
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    if grep -qF "[${username}-versions]" "$smb_conf" 2>/dev/null; then
        echo "Read-only SMB access to versions is already enabled for user '$username'"
        return 0
    fi
    
    echo "Enabling read-only SMB access to versions for user '$username'..."
    
    # Append versions share to the user's existing Samba config file
    # This ensures Samba loads it properly (same file as the backup share)
    mkdir -p /etc/samba/smb.conf.d
    
    cat >> "$smb_conf" << EOF

# Read-only access to backup snapshots for disaster recovery
[$username-versions]
   path = /home/$username/versions
   comment = Read-only backup snapshots for $username
   browseable = yes
   read only = yes
   writable = no
   guest ok = no
   valid users = $username
   force user = $username
   force group = backupusers
   # Strict security settings
   public = no
   printable = no
   create mask = 0000
   directory mask = 0000
   # VFS audit module for tracking access
   vfs objects = full_audit
   full_audit:prefix = %u|%I|%m|versions
   full_audit:success = connect disconnect open readdir
   full_audit:failure = none
   full_audit:facility = local5
   full_audit:priority = notice
EOF
    
    # Update main smb.conf to reload includes (picks up the new share)
    update_samba_includes
    
    # Restart Samba services (reload might not pick up new shares immediately)
    systemctl restart smbd nmbd
    
    echo "=========================================="
    echo "✓ Read-only SMB access to versions enabled"
    echo "=========================================="
    echo ""
    echo "Share details:"
    echo "  Share name: //$HOSTNAME/$username-versions"
    echo "  Path: /home/$username/versions"
    echo "  Access: Read-only"
    echo "  User: $username"
    echo ""
    echo "Windows access:"
    echo "  \\\\$HOSTNAME\\$username-versions"
    echo ""
    echo "Security notes:"
    echo "  • Snapshots are read-only and cannot be modified"
    echo "  • All access is logged via VFS audit"
    echo "  • SMB3 encryption is enforced"
    echo "  • Only user '$username' can access this share"
    echo ""
    echo "To disable: $SCRIPT_NAME disable-samba-versions $username"
}

# Disable read-only Samba access to versions directory
disable_samba_versions() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        return 1
    fi
    
    # Check if enabled (check in user's main config file)
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    if [ ! -f "$smb_conf" ] || ! grep -qF "[${username}-versions]" "$smb_conf" 2>/dev/null; then
        echo "Read-only SMB access to versions is not enabled for user '$username'"
        return 0
    fi
    
    echo "Disabling read-only SMB access to versions for user '$username'..."
    
    # Remove the versions share section from the user's config file
    # Use sed to delete from [username-versions] to the next section or EOF
    sed -i "/^\[${username}-versions\]/,/^\[/{ /^\[${username}-versions\]/d; /^\[/!d; }" "$smb_conf"
    # Also handle case where versions section is at the end of file (no next section)
    sed -i "/^\[${username}-versions\]/,\$d" "$smb_conf"
    
    echo "  Removed versions share from Samba configuration"
    
    # Update main smb.conf (no change needed as we still include the same file)
    # But we reload includes anyway for consistency
    update_samba_includes
    
    # Restart Samba services (reload doesn't always work for removing shares)
    systemctl restart smbd nmbd
    
    echo "✓ Read-only SMB access to versions disabled for user '$username'"
}

# Enable macOS Time Machine support for a user
enable_timemachine() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if user is in backupusers group
    if ! id "$username" | grep -q "backupusers"; then
        echo "Error: User '$username' is not a backup user" >&2
        return 1
    fi
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        echo "Time Machine requires Samba. Please run setup.sh first."
        return 1
    fi
    
    # Check if Samba is enabled first
    if ! has_samba_enabled "$username"; then
        echo "Error: Samba is not enabled for user '$username'"
        echo "Please enable Samba first: $SCRIPT_NAME enable-samba $username"
        return 1
    fi
    
    # Check if Time Machine is already enabled
    if has_timemachine_enabled "$username"; then
        echo "Time Machine support is already enabled for user '$username'"
        return 0
    fi
    
    echo "Enabling Time Machine support for user '$username'..."
    
    local home_dir="/home/${username}"
    local uploads_dir="${home_dir}/uploads"
    
    # Create Time Machine share configuration
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    cat >> "$smb_conf" <<EOF

[${username}-timemachine]
   comment = Time Machine Backup for ${username}
   path = ${uploads_dir}
   browseable = yes
   writable = yes
   read only = no
   create mask = 0700
   directory mask = 0700
   valid users = ${username}
   vfs objects = fruit streams_xattr full_audit
   fruit:aapl = yes
   fruit:time machine = yes
   fruit:time machine max size = 0
   # VFS audit module for tracking Time Machine connections
   full_audit:prefix = %u|%I|%m|timemachine
   full_audit:success = connect disconnect open close write pwrite
   full_audit:failure = connect
   full_audit:facility = local1
   full_audit:priority = notice
EOF
    
    echo "  Added Time Machine share to Samba configuration"
    
    # Update main smb.conf (no change needed as we still include the same file)
    # But we reload includes anyway for consistency
    update_samba_includes
    
    # Restart Samba services (reload doesn't always work for new shares)
    systemctl restart smbd nmbd
    
    echo "✓ Time Machine support enabled for user '$username'"
    echo ""
    echo "macOS Setup Instructions:"
    echo "1. Connect to the share in Finder first:"
    echo "   - Open Finder → Go → Connect to Server (or press Command+K)"
    echo "   - Enter: smb://<server-ip>/${username}-timemachine"
    echo "   - Click Connect and enter credentials:"
    echo "     Username: ${username}"
    echo "     Password: [user's Samba password]"
    echo ""
    echo "2. Configure Time Machine:"
    echo "   - Open System Preferences → Time Machine"
    echo "   - Click '+' (Add Disk) or 'Select Disk'"
    echo "   - Select '${username}-timemachine' from the list"
    echo "   - Time Machine will now use this network share for backups"
    echo ""
    echo "Note: Bakap's monitoring service will automatically create snapshots"
    echo "      when Time Machine writes files to the uploads directory."
}

# Disable macOS Time Machine support for a user
disable_timemachine() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo "Error: Username is required" >&2
        return 1
    fi
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if Samba is installed
    if ! command -v smbpasswd &>/dev/null; then
        echo "ERROR: Samba is not installed on this server."
        return 1
    fi
    
    # Check if enabled (check in user's main config file)
    local smb_conf="/etc/samba/smb.conf.d/${username}.conf"
    if [ ! -f "$smb_conf" ] || ! grep -qF "[${username}-timemachine]" "$smb_conf" 2>/dev/null; then
        echo "Time Machine support is not enabled for user '$username'"
        return 0
    fi
    
    echo "Disabling Time Machine support for user '$username'..."
    
    # Remove the timemachine share section from the user's config file
    # Use sed to delete from [username-timemachine] to the next section or EOF
    sed -i "/^\[${username}-timemachine\]/,/^\[/{ /^\[${username}-timemachine\]/d; /^\[/!d; }" "$smb_conf"
    # Also handle case where timemachine section is at the end of file (no next section)
    sed -i "/^\[${username}-timemachine\]/,\$d" "$smb_conf"
    
    echo "  Removed Time Machine share from Samba configuration"
    
    # Update main smb.conf (no change needed as we still include the same file)
    # But we reload includes anyway for consistency
    update_samba_includes
    
    # Restart Samba services (reload doesn't always work for removing shares)
    systemctl restart smbd nmbd
    
    echo "✓ Time Machine support disabled for user '$username'"
    echo ""
    echo "Note: Existing backups in the uploads directory are not deleted."
    echo "      The user can still access files via SFTP or the main SMB share."
}

# List all backup users with their disk usage
list_users() {
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    # Check if any user has Samba enabled (determines if we show SMB column)
    local any_samba=false
    while IFS= read -r user; do
        if [ -n "$user" ] && has_samba_enabled "$user"; then
            any_samba=true
            break
        fi
    done <<< "$users"
    
    # Display header immediately before doing heavy processing
    echo "Backup Users:"
    if [ "$any_samba" = true ]; then
        echo "=============================================================================================================================================="
        printf "%-16s %8s %8s %6s %8s %19s %16s %16s %s\n" "Username" "Size(MB)" "Apparent" "Snaps" "Protocol" "Last Snapshot" "Last SFTP" "Last SMB" "Status"
        echo "----------------------------------------------------------------------------------------------------------------------------------------------"
    else
        echo "=================================================================================================================================="
        printf "%-16s %8s %8s %6s %8s %19s %19s %s\n" "Username" "Size(MB)" "Apparent" "Snaps" "Protocol" "Last Snapshot" "Last SFTP" "Status"
        echo "----------------------------------------------------------------------------------------------------------------------------------"
    fi
    
    # Build connection caches once for all users (performance optimization)
    build_connection_cache
    if [ "$any_samba" = true ]; then
        build_samba_connection_cache
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
        
        # Calculate sizes using Btrfs-aware method
        local actual_size="0.00"
        local apparent_size="0.00"
        
        # Try to get actual physical usage from btrfs filesystem du
        if command -v btrfs &>/dev/null; then
            local btrfs_output=$(btrfs filesystem du -s "$home_dir" 2>/dev/null)
            if [ -n "$btrfs_output" ]; then
                local data_line=$(echo "$btrfs_output" | tail -1)
                local exclusive_raw=$(echo "$data_line" | awk '{print $2}')
                local shared_raw=$(echo "$data_line" | awk '{print $3}')
                
                # Convert to MB
                local exclusive_mb=$(echo "$exclusive_raw" | awk '{
                    size=$1;
                    if (size ~ /GiB/) { gsub(/[^0-9.]/, "", size); print size * 1024 }
                    else if (size ~ /MiB/) { gsub(/[^0-9.]/, "", size); print size }
                    else if (size ~ /KiB/) { gsub(/[^0-9.]/, "", size); print size / 1024 }
                    else if (size ~ /B$/) { gsub(/[^0-9.]/, "", size); print size / 1024 / 1024 }
                    else { print size / 1024 / 1024 }
                }')
                
                local shared_mb=$(echo "$shared_raw" | awk '{
                    size=$1;
                    if (size ~ /GiB/) { gsub(/[^0-9.]/, "", size); print size * 1024 }
                    else if (size ~ /MiB/) { gsub(/[^0-9.]/, "", size); print size }
                    else if (size ~ /KiB/) { gsub(/[^0-9.]/, "", size); print size / 1024 }
                    else if (size ~ /B$/) { gsub(/[^0-9.]/, "", size); print size / 1024 / 1024 }
                    else if (size == "-") { print 0 }
                    else { print size / 1024 / 1024 }
                }')
                
                actual_size=$(echo "scale=2; ($exclusive_mb + $shared_mb) / 1" | bc)
            fi
        fi
        
        # Fallback to du if btrfs command failed
        if [ "$actual_size" = "0.00" ]; then
            actual_size=$(get_actual_size "$home_dir")
        fi
        
        # Calculate logical size (sum of all files in uploads + all snapshots)
        local uploads_logical=$(get_apparent_size "$home_dir/uploads")
        local snapshots_logical="0.00"
        
        # Count snapshots and calculate logical size
        local snapshot_count=0
        if [ -d "$home_dir/versions" ]; then
            snapshot_count=$(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            
            # Sum logical sizes of all snapshots
            while IFS= read -r snapshot; do
                if [ -n "$snapshot" ] && [ -d "$snapshot" ]; then
                    # Calculate MB directly in awk to avoid scientific notation issues
                    local snap_mb=$(find "$snapshot" -type f -exec stat -c %s {} \; 2>/dev/null | awk '{sum+=$1} END {printf "%.2f", sum/1024/1024}')
                    if [ -n "$snap_mb" ] && [ "$snap_mb" != "0.00" ]; then
                        snapshots_logical=$(echo "$snapshots_logical + $snap_mb" | bc)
                    fi
                fi
            done < <(find "$home_dir/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        fi
        
        apparent_size=$(echo "scale=2; ($uploads_logical + $snapshots_logical) / 1" | bc)
        
        # Get last backup date
        local backup_info=$(get_last_backup_date "$user")
        local last_date=$(echo "$backup_info" | cut -d'|' -f1)
        local last_epoch=$(echo "$backup_info" | cut -d'|' -f2)
        
        # Get last connection time
        local conn_info=$(get_last_connection "$user")
        local last_conn=$(echo "$conn_info" | cut -d'|' -f1)
        local conn_epoch=$(echo "$conn_info" | cut -d'|' -f2)
        
        # Determine status with improved logic
        local status="OK"
        local status_color=""
        
        if [ "$last_date" = "Never" ] && [ "$last_conn" = "Never" ]; then
            # No backup and no connection - never used
            status="⚠ NEVER USED"
            status_color="\033[1;33m"  # Yellow
        elif [ "$last_date" = "Never" ] && [ "$last_conn" != "Never" ]; then
            # Connected but no snapshot yet (new user or files still uploading)
            local conn_days=$(( (now - conn_epoch) / 86400 ))
            status="⚠ No snapshot (conn: ${conn_days}d)"
            status_color="\033[1;33m"  # Yellow
        elif [ "$last_epoch" -gt 0 ]; then
            local backup_days=$(( (now - last_epoch) / 86400 ))
            
            # Check if connection is more recent than backup (no changes scenario)
            if [ "$conn_epoch" -gt "$last_epoch" ]; then
                # Connected after last backup = backup running but no changes
                local conn_days=$(( (now - conn_epoch) / 86400 ))
                if [ $backup_days -gt 15 ]; then
                    status="✓ No changes (${backup_days}d)"
                    status_color="\033[0;32m"  # Green (this is good!)
                else
                    status="✓ OK (${backup_days}d)"
                    status_color="\033[0;32m"  # Green
                fi
            else
                # Last backup more recent than connection (or no connection logged)
                if [ $backup_days -gt 15 ]; then
                    status="⚠ ${backup_days}d ago"
                    status_color="\033[1;33m"  # Yellow
                else
                    status="✓ OK (${backup_days}d)"
                    status_color="\033[0;32m"  # Green
                fi
            fi
        fi
        
        # Format dates for display (keep full date/time)
        local display_backup="$last_date"
        local display_sftp="$last_conn"
        
        # Get Samba connection info if enabled
        local display_smb="N/A"
        if [ "$any_samba" = true ]; then
            if has_samba_enabled "$user"; then
                local smb_info=$(get_last_samba_connection "$user")
                display_smb=$(echo "$smb_info" | cut -d'|' -f1)
            fi
        fi
        
        # Determine protocol support
        local protocol="SFTP"
        if has_samba_enabled "$user"; then
            protocol="SMB+SFTP"
            # Add markers for additional features
            local has_versions="no"
            local has_tm="no"
            if has_samba_versions_enabled "$user" 2>/dev/null; then
                has_versions="yes"
            fi
            if has_timemachine_enabled "$user" 2>/dev/null; then
                has_tm="yes"
            fi
            
            if [ "$has_versions" = "yes" ] && [ "$has_tm" = "yes" ]; then
                protocol="SMB*TM+SFTP"
            elif [ "$has_versions" = "yes" ]; then
                protocol="SMB*+SFTP"
            elif [ "$has_tm" = "yes" ]; then
                protocol="SMBTM+SFTP"
            fi
        fi
        
        # Print with color - adjust format based on whether Samba column is shown
        if [ "$any_samba" = true ]; then
            if [ -n "$status_color" ] && [ "$status" != "✓"* ]; then
                printf "%-16s %8s %8s %6s %8s %19s %16s %16s ${status_color}%s\033[0m\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$protocol" "$display_backup" "$display_sftp" "$display_smb" "$status"
            else
                printf "%-16s %8s %8s %6s %8s %19s %16s %16s %s\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$protocol" "$display_backup" "$display_sftp" "$display_smb" "$status"
            fi
        else
            if [ -n "$status_color" ] && [ "$status" != "✓"* ]; then
                printf "%-16s %8s %8s %6s %8s %19s %19s ${status_color}%s\033[0m\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$protocol" "$display_backup" "$display_sftp" "$status"
            else
                printf "%-16s %8s %8s %6s %8s %19s %19s %s\n" "$user" "$actual_size" "$apparent_size" "$snapshot_count" "$protocol" "$display_backup" "$display_sftp" "$status"
            fi
        fi
        
        # Sum up totals using bc for decimal arithmetic
        total_actual=$(echo "$total_actual + $actual_size" | bc)
        total_apparent=$(echo "$total_apparent + $apparent_size" | bc)
        total_users=$((total_users + 1))
    done <<< "$users"
    
    # Print footer with appropriate line length
    if [ "$any_samba" = true ]; then
        echo "----------------------------------------------------------------------------------------------------------------------------------------------"
        printf "%-16s %8s %8s %6s %8s\n" "Total: $total_users" "$total_actual" "$total_apparent" "" ""
    else
        echo "----------------------------------------------------------------------------------------------------------------------------------"
        printf "%-16s %8s %8s %6s %8s\n" "Total: $total_users" "$total_actual" "$total_apparent" "" ""
    fi
    
    echo ""
    echo "Note: Size(MB) shows physical disk usage with Btrfs deduplication"
    echo "      Apparent shows logical size (sum of all files as if independent copies)"
    echo "      The difference shows space saved by Btrfs CoW snapshots"
    echo "      Protocol shows available access methods (SFTP or SMB+SFTP)"
    echo "      SMB* = Read-only versions access enabled (disable with 'disable-samba-versions <user>')"
    echo "      Last Snapshot shows when the most recent snapshot was created"
    echo "      Last SFTP shows most recent SSH/SFTP authentication"
    if [ "$any_samba" = true ]; then
        echo "      Last SMB shows most recent Samba/SMB connection (N/A if Samba not enabled for user)"
    fi
    echo "      Status meanings:"
    echo "        ✓ OK           = Recent snapshot or connection with no changes (good!)"
    echo "        ✓ No changes   = Backup job running but no file changes detected"
    echo "        ⚠ NEVER USED   = User never connected"
    echo "        ⚠ No snapshot  = Connected but no snapshot created yet"
    echo "        ⚠ Xd ago       = Last snapshot more than 15 days old"
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
    
    # Build connection caches for lookups
    build_connection_cache
    build_samba_connection_cache
    
    # Connection activity
    local conn_info=$(get_last_connection "$username")
    local last_conn=$(echo "$conn_info" | cut -d'|' -f1)
    local conn_epoch=$(echo "$conn_info" | cut -d'|' -f2)
    
    # Get SMB connection info if Samba is enabled
    local samba_conn="Never"
    local samba_epoch=0
    if has_samba_enabled "$username"; then
        local samba_info="${SAMBA_CONNECTION_CACHE[$username]}"
        if [ -n "$samba_info" ]; then
            samba_conn=$(echo "$samba_info" | cut -d'|' -f1)
            samba_epoch=$(echo "$samba_info" | cut -d'|' -f2)
        fi
    fi
    
    echo "Connection Activity:"
    
    # Display SFTP/SSH connection
    if [ "$last_conn" != "Never" ] && [ "$conn_epoch" -gt 0 ]; then
        local now=$(date +%s)
        local days_ago=$(( (now - conn_epoch) / 86400 ))
        local hours_ago=$(( (now - conn_epoch) / 3600 ))
        
        echo "  Last SFTP:       $last_conn"
        if [ $hours_ago -lt 24 ]; then
            echo "                   ${hours_ago} hours ago"
        else
            echo "                   ${days_ago} days ago"
        fi
    else
        echo "  Last SFTP:       Never"
    fi
    
    # Display SMB connection if Samba is enabled
    if has_samba_enabled "$username"; then
        if [ "$samba_conn" != "Never" ] && [ "$samba_epoch" -gt 0 ]; then
            local now=$(date +%s)
            local days_ago=$(( (now - samba_epoch) / 86400 ))
            local hours_ago=$(( (now - samba_epoch) / 3600 ))
            
            echo "  Last SMB:        $samba_conn"
            if [ $hours_ago -lt 24 ]; then
                echo "                   ${hours_ago} hours ago"
            else
                echo "                   ${days_ago} days ago"
            fi
        else
            echo "  Last SMB:        Never"
        fi
    fi
    echo ""
    
    # Disk usage - check if directories have actual files first
    local has_files=0
    if [ -n "$(find "$home_dir/uploads" -type f 2>/dev/null | head -1)" ] || \
       [ -n "$(find "$home_dir/versions" -type f 2>/dev/null | head -1)" ]; then
        has_files=1
    fi
    
    if [ "$has_files" -eq 1 ]; then
        # Use btrfs filesystem du for accurate shared/exclusive breakdown
        local versions_dir="$home_dir/versions"
        local snapshot_count=0
        local total_logical_size="0.00"
        local uploads_logical=$(get_apparent_size "$home_dir/uploads")
        
        if [ -d "$versions_dir" ]; then
            snapshot_count=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            
            # Sum logical file sizes for all snapshots
            while IFS= read -r snapshot; do
                if [ -n "$snapshot" ] && [ -d "$snapshot" ]; then
                    # Calculate MB directly in awk to avoid scientific notation issues
                    local snapshot_mb=$(find "$snapshot" -type f -exec stat -c %s {} \; 2>/dev/null | awk '{sum+=$1} END {printf "%.2f", sum/1024/1024}')
                    if [ -n "$snapshot_mb" ] && [ "$snapshot_mb" != "0.00" ]; then
                        total_logical_size=$(echo "$total_logical_size + $snapshot_mb" | bc)
                    fi
                fi
            done < <(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        fi
        
        # Calculate logical size (what it would be without Btrfs CoW)
        local total_logical=$(echo "$uploads_logical + $total_logical_size" | bc)
        
        # Try to get actual physical usage using btrfs filesystem du
        local physical_usage=""
        local space_saved=""
        local efficiency_pct="0"
        local exclusive_size=""
        local shared_size=""
        
        if command -v btrfs &>/dev/null; then
            # Get exclusive + shared bytes for the home directory
            local btrfs_output=$(btrfs filesystem du -s "$home_dir" 2>/dev/null)
            if [ -n "$btrfs_output" ]; then
                # Parse: "Total   Exclusive  Set shared  Filename"
                # Extract Exclusive and Set shared columns
                local data_line=$(echo "$btrfs_output" | tail -1)
                
                # Extract exclusive size (2nd column)
                local exclusive_raw=$(echo "$data_line" | awk '{print $2}')
                # Extract set shared size (3rd column)
                local shared_raw=$(echo "$data_line" | awk '{print $3}')
                
                # Convert to MB
                exclusive_size=$(echo "$exclusive_raw" | awk '{
                    size=$1;
                    if (size ~ /GiB/) { gsub(/[^0-9.]/, "", size); print size * 1024 }
                    else if (size ~ /MiB/) { gsub(/[^0-9.]/, "", size); print size }
                    else if (size ~ /KiB/) { gsub(/[^0-9.]/, "", size); print size / 1024 }
                    else if (size ~ /B$/) { gsub(/[^0-9.]/, "", size); print size / 1024 / 1024 }
                    else { print size / 1024 / 1024 }
                }')
                
                shared_size=$(echo "$shared_raw" | awk '{
                    size=$1;
                    if (size ~ /GiB/) { gsub(/[^0-9.]/, "", size); print size * 1024 }
                    else if (size ~ /MiB/) { gsub(/[^0-9.]/, "", size); print size }
                    else if (size ~ /KiB/) { gsub(/[^0-9.]/, "", size); print size / 1024 }
                    else if (size ~ /B$/) { gsub(/[^0-9.]/, "", size); print size / 1024 / 1024 }
                    else if (size == "-") { print 0 }
                    else { print size / 1024 / 1024 }
                }')
                
                # Physical usage = exclusive + shared (but shared is counted once across all subvolumes)
                # The real physical storage is approximately: shared_size + exclusive_size
                local physical_mb=$(echo "$shared_size + $exclusive_size" | bc)
                
                space_saved=$(echo "$total_logical - $physical_mb" | bc)
                physical_usage="${physical_mb} MB"
                
                if [ $(echo "$total_logical > 0" | bc) -eq 1 ]; then
                    efficiency_pct=$(echo "scale=1; ($space_saved / $total_logical) * 100" | bc)
                fi
            fi
        fi
        
        # Fallback to du-based calculation if btrfs filesystem du failed
        if [ -z "$physical_usage" ]; then
            local actual_size=$(get_actual_size "$home_dir")
            space_saved=$(echo "$total_logical - $actual_size" | bc)
            physical_usage="${actual_size} MB"
            
            if [ $(echo "$total_logical > 0" | bc) -eq 1 ]; then
                efficiency_pct=$(echo "scale=1; ($space_saved / $total_logical) * 100" | bc)
            fi
        fi
        
        echo "Disk Usage:"
        echo "  Uploads:            ${uploads_logical} MB (current files)"
        echo "  Snapshots (${snapshot_count}):       ${total_logical_size} MB (logical size)"
        echo "  Total logical:      ${total_logical} MB (sum of all files)"
        echo "  Physical usage:     ${physical_usage} (with Btrfs deduplication)"
        echo "  Space saved:        ${space_saved} MB (${efficiency_pct}% efficient)"
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
            # Sort by modification time (creation time of snapshot), not alphabetically
            # This handles snapshots with non-standard names like test_manual_*
            local oldest=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
            local newest=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            
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
    
    # Kill any processes owned by the user
    pkill -u "$username" 2>/dev/null || true
    
    # Delete user account
    userdel "$username" 2>/dev/null || true
    
    # Remove Samba user if exists
    if command -v smbpasswd &>/dev/null; then
        smbpasswd -x "$username" 2>/dev/null || true
    fi
    
    # Remove Samba configuration
    if [ -f "/etc/samba/smb.conf.d/$username.conf" ]; then
        rm -f "/etc/samba/smb.conf.d/$username.conf"
        
        # Also remove from main smb.conf
        if [ -f /etc/samba/smb.conf ]; then
            # Remove the share section (from comment line to next blank line or EOF)
            sed -i "/^# Share for user: $username$/,/^$/d" /etc/samba/smb.conf
            # Fallback: remove share block if comment line doesn't exist
            sed -i "/^\[$username-backup\]$/,/^$/d" /etc/samba/smb.conf
        fi
        
        # Restart Samba to apply changes
        systemctl restart smbd 2>/dev/null || true
    fi
    
    # Remove home directory and all Btrfs subvolumes
    if [ -d "/home/$username" ]; then
        echo "Removing Btrfs subvolumes and data..."
        
        # Delete uploads subvolume
        if [ -d "/home/$username/uploads" ]; then
            if btrfs subvolume show "/home/$username/uploads" &>/dev/null; then
                echo "  Deleting uploads subvolume..."
                btrfs subvolume delete "/home/$username/uploads" >/dev/null 2>&1 || rm -rf "/home/$username/uploads"
            else
                rm -rf "/home/$username/uploads"
            fi
        fi
        
        # Delete all snapshot subvolumes in versions/
        if [ -d "/home/$username/versions" ]; then
            echo "  Deleting snapshot subvolumes..."
            local count=0
            for snapshot in /home/$username/versions/*; do
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
            rmdir "/home/$username/versions" 2>/dev/null || rm -rf "/home/$username/versions"
        fi
        
        # Remove home directory
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
    
    # With Btrfs snapshots, we don't need to "consolidate" like with hardlinks
    # Just remove all old snapshots except the latest
    echo "Removing $((snapshot_count - 1)) old Btrfs snapshot(s)..."
    
    local removed=0
    while IFS= read -r snapshot; do
        if [ -n "$snapshot" ] && [ -d "$snapshot" ] && [ "$snapshot" != "$latest_snapshot" ]; then
            # Check if it's a Btrfs subvolume
            if btrfs subvolume show "$snapshot" &>/dev/null; then
                # Make snapshot writable before deletion
                btrfs property set -ts "$snapshot" ro false 2>/dev/null || true
                if btrfs subvolume delete "$snapshot" &>/dev/null; then
                    removed=$((removed + 1))
                fi
            else
                # Fallback for non-subvolume directories
                rm -rf "$snapshot" && removed=$((removed + 1))
            fi
        fi
    done <<< "$snapshots"
    
    # Calculate space after cleanup
    local size_after=$(get_actual_size "$versions_dir")
    local space_freed=$(echo "$size_before - $size_after" | bc)
    
    echo "Cleanup complete for user '$username'"
    echo "Removed $removed old snapshots"
    echo "Space before: ${size_before} MB"
    echo "Space after: ${size_after} MB"
    echo "Space freed: ${space_freed} MB"
    echo "Latest snapshot preserved: $latest_name"
}

# Check if user has open files in uploads directory
has_open_files() {
    local username="$1"
    local home_dir="/home/$username"
    local uploads_dir="$home_dir/uploads"
    
    if [ ! -d "$uploads_dir" ]; then
        return 1  # No uploads dir = no open files
    fi
    
    # Check for open files using lsof
    local open_files=$(lsof +D "$uploads_dir" 2>/dev/null | grep -E "\s+[0-9]+[uw]" || true)
    
    if [ -n "$open_files" ]; then
        return 0  # Has open files
    else
        return 1  # No open files
    fi
}

# Verify file integrity between uploads and snapshot
verify_snapshot_integrity() {
    local username="$1"
    local snapshot_path="$2"
    local uploads_dir="/home/$username/uploads"
    
    echo "Verifying file integrity..."
    
    # Count files in uploads
    local uploads_count=$(find "$uploads_dir" -type f 2>/dev/null | wc -l)
    local snapshot_count=$(find "$snapshot_path" -type f 2>/dev/null | wc -l)
    
    if [ "$uploads_count" -ne "$snapshot_count" ]; then
        echo "⚠ WARNING: File count mismatch! Uploads: $uploads_count, Snapshot: $snapshot_count"
        return 1
    fi
    
    echo "✓ File count matches: $uploads_count files"
    
    # Compare file sizes and checksums for each file
    local errors=0
    local checked=0
    
    while IFS= read -r upload_file; do
        if [ -f "$upload_file" ]; then
            local rel_path="${upload_file#$uploads_dir/}"
            local snapshot_file="$snapshot_path/$rel_path"
            
            if [ ! -f "$snapshot_file" ]; then
                echo "✗ Missing in snapshot: $rel_path"
                errors=$((errors + 1))
            else
                # Compare file sizes
                local upload_size=$(stat -c %s "$upload_file" 2>/dev/null || stat -f %z "$upload_file" 2>/dev/null)
                local snapshot_size=$(stat -c %s "$snapshot_file" 2>/dev/null || stat -f %z "$snapshot_file" 2>/dev/null)
                
                if [ "$upload_size" != "$snapshot_size" ]; then
                    echo "✗ Size mismatch: $rel_path (upload: $upload_size, snapshot: $snapshot_size)"
                    errors=$((errors + 1))
                fi
                
                checked=$((checked + 1))
            fi
        fi
    done < <(find "$uploads_dir" -type f 2>/dev/null)
    
    if [ "$errors" -eq 0 ]; then
        echo "✓ All $checked files verified successfully"
        return 0
    else
        echo "✗ Verification failed: $errors errors found"
        return 1
    fi
}

# Rebuild snapshots for a single user
rebuild_user() {
    local username="$1"
    local skip_confirmation="${2:-false}"  # Optional parameter, defaults to false
    
    # Validate user
    if ! id "$username" &>/dev/null; then
        echo "Error: User '$username' does not exist" >&2
        return 1
    fi
    
    # Check if user is a backup user
    local backup_users=$(get_backup_users)
    if ! echo "$backup_users" | grep -q "^${username}$"; then
        echo "Error: User '$username' is not a backup user" >&2
        return 1
    fi
    
    local home_dir="/home/$username"
    local uploads_dir="$home_dir/uploads"
    local versions_dir="$home_dir/versions"
    
    echo "=========================================="
    echo "Rebuilding snapshots for user: $username"
    echo "=========================================="
    
    # Confirmation prompt (skip if called from rebuild_all)
    if [ "$skip_confirmation" != "true" ]; then
        # Count existing snapshots for confirmation message
        local existing_count=0
        if [ -d "$versions_dir" ]; then
            existing_count=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        fi
        
        echo "WARNING: This will DELETE ALL existing snapshots for user '$username' and create a fresh one!"
        if [ "$existing_count" -gt 0 ]; then
            echo "Existing snapshots to be deleted: $existing_count"
        fi
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            echo "Rebuild cancelled for user '$username'."
            return 1
        fi
        echo ""
    fi
    
    # Check if uploads directory exists
    if [ ! -d "$uploads_dir" ]; then
        echo "⚠ WARNING: No uploads directory found for user '$username'"
        echo "Skipping this user."
        return 1
    fi
    
    # Check for open files
    if has_open_files "$username"; then
        echo "⚠ WARNING: User '$username' has files currently open in uploads directory"
        echo "Cannot rebuild while files are in progress. Skipping this user."
        local open_files=$(lsof +D "$uploads_dir" 2>/dev/null | grep -E "\s+[0-9]+[uw]" | awk '{print $NF}')
        echo "Open files:"
        echo "$open_files" | while IFS= read -r file; do
            if [ -n "$file" ]; then
                echo "  - ${file#$uploads_dir/}"
            fi
        done
        return 1
    fi
    
    # Check if uploads directory has any files
    local file_count=$(find "$uploads_dir" -type f 2>/dev/null | wc -l)
    if [ "$file_count" -eq 0 ]; then
        echo "⚠ WARNING: Uploads directory is empty for user '$username'"
        echo "Skipping this user."
        return 1
    fi
    
    echo "✓ No open files detected"
    echo "Files to snapshot: $file_count"
    
    # Delete all existing snapshots
    if [ -d "$versions_dir" ]; then
        local snapshots=$(find "$versions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        local snapshot_count=$(echo "$snapshots" | grep -v '^$' | wc -l)
        
        if [ "$snapshot_count" -gt 0 ]; then
            echo "Deleting $snapshot_count existing snapshot(s)..."
            
            local deleted=0
            while IFS= read -r snapshot; do
                if [ -n "$snapshot" ] && [ -d "$snapshot" ]; then
                    # Try to make writable first if it's read-only
                    btrfs property set -ts "$snapshot" ro false &>/dev/null || true
                    
                    # Check if it's a Btrfs subvolume
                    if btrfs subvolume show "$snapshot" &>/dev/null; then
                        if btrfs subvolume delete "$snapshot" &>/dev/null; then
                            deleted=$((deleted + 1))
                            echo "  ✓ Deleted: $(basename "$snapshot")"
                        else
                            echo "  ✗ Failed to delete: $(basename "$snapshot")"
                        fi
                    else
                        # Fallback for non-subvolume directories
                        if rm -rf "$snapshot"; then
                            deleted=$((deleted + 1))
                            echo "  ✓ Deleted: $(basename "$snapshot")"
                        else
                            echo "  ✗ Failed to delete: $(basename "$snapshot")"
                        fi
                    fi
                fi
            done <<< "$snapshots"
            
            echo "Deleted $deleted snapshot(s)"
        else
            echo "No existing snapshots to delete"
        fi
    else
        echo "Creating versions directory..."
        mkdir -p "$versions_dir"
        chown root:backupusers "$versions_dir"
        chmod 755 "$versions_dir"
    fi
    
    # Create fresh snapshot from uploads
    echo "Creating fresh snapshot from uploads directory..."
    
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local snapshot_path="$versions_dir/$timestamp"
    
    # Check if uploads is a Btrfs subvolume
    if btrfs subvolume show "$uploads_dir" &>/dev/null; then
        # Create Btrfs snapshot
        if btrfs subvolume snapshot "$uploads_dir" "$snapshot_path" &>/dev/null; then
            echo "✓ Btrfs snapshot created: $timestamp"
            
            # Make snapshot read-only for ransomware protection
            if btrfs property set -ts "$snapshot_path" ro true &>/dev/null; then
                echo "✓ Snapshot set to read-only"
            else
                echo "⚠ WARNING: Failed to set snapshot as read-only"
            fi
            
            # Set ownership and permissions
            chown root:backupusers "$snapshot_path" 2>/dev/null || true
            chmod 755 "$snapshot_path" 2>/dev/null || true
            
            # Verify integrity
            if verify_snapshot_integrity "$username" "$snapshot_path"; then
                echo "✓ Snapshot rebuild completed successfully for user '$username'"
                return 0
            else
                echo "✗ Snapshot created but integrity verification failed"
                return 1
            fi
        else
            echo "✗ ERROR: Failed to create Btrfs snapshot"
            return 1
        fi
    else
        echo "✗ ERROR: Uploads directory is not a Btrfs subvolume"
        echo "This should not happen. Please check the user setup."
        return 1
    fi
}

# Rebuild snapshots for all users
rebuild_all() {
    echo "=========================================="
    echo "Rebuilding snapshots for all backup users"
    echo "=========================================="
    echo ""
    
    local users=$(get_backup_users)
    if [ -z "$users" ]; then
        echo "No backup users found."
        return
    fi
    
    # Count total users and snapshots for confirmation
    local user_count=$(echo "$users" | grep -v '^$' | wc -l)
    local total_snapshots=0
    
    while IFS= read -r user; do
        if [ -n "$user" ] && [ -d "/home/$user/versions" ]; then
            local count=$(find "/home/$user/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            total_snapshots=$((total_snapshots + count))
        fi
    done <<< "$users"
    
    # Confirmation prompt
    echo "WARNING: This will DELETE ALL existing snapshots for ALL backup users!"
    echo "Total users: $user_count"
    echo "Total snapshots to be deleted: $total_snapshots"
    echo "Each user will get a fresh snapshot created from their current uploads."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Rebuild cancelled."
        return
    fi
    echo ""
    
    local processed=0
    local succeeded=0
    local skipped=0
    local failed=0
    
    while IFS= read -r user; do
        if [ -z "$user" ]; then
            continue
        fi
        
        processed=$((processed + 1))
        
        # Pass 'true' as second parameter to skip individual confirmation prompts
        if rebuild_user "$user" "true"; then
            succeeded=$((succeeded + 1))
        else
            # Check if it was skipped or failed
            if has_open_files "$user" 2>/dev/null; then
                skipped=$((skipped + 1))
            else
                failed=$((failed + 1))
            fi
        fi
        
        echo ""
    done <<< "$users"
    
    echo "=========================================="
    echo "Rebuild Summary"
    echo "=========================================="
    echo "Total users processed: $processed"
    echo "Successfully rebuilt: $succeeded"
    echo "Skipped (open files): $skipped"
    echo "Failed: $failed"
    echo "=========================================="
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
    rebuild)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for rebuild command" >&2
            usage
            exit 1
        fi
        rebuild_user "$1"
        ;;
    rebuild-all)
        rebuild_all
        ;;
    enable-samba)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for enable-samba command" >&2
            usage
            exit 1
        fi
        enable_samba "$1"
        ;;
    disable-samba)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for disable-samba command" >&2
            usage
            exit 1
        fi
        disable_samba "$1"
        ;;
    enable-samba-versions)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for enable-samba-versions command" >&2
            usage
            exit 1
        fi
        enable_samba_versions "$1"
        ;;
    disable-samba-versions)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for disable-samba-versions command" >&2
            usage
            exit 1
        fi
        disable_samba_versions "$1"
        ;;
    enable-timemachine)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for enable-timemachine command" >&2
            usage
            exit 1
        fi
        enable_timemachine "$1"
        ;;
    disable-timemachine)
        if [ $# -eq 0 ]; then
            echo "Error: Username is required for disable-timemachine command" >&2
            usage
            exit 1
        fi
        disable_timemachine "$1"
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
