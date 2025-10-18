#!/usr/bin/env bash
#
# Comprehensive script to rename bakap to termiNAS throughout the project
# Copyright (c) 2025 Yianni Bourkelis
# MIT License
#

set -e

echo "=================================================="
echo "termiNAS Renaming Script"
echo "=================================================="
echo "This script will rename all bakap references to termiNAS"
echo ""
echo "Changes will include:"
echo "  - File paths: /opt/bakap → /opt/terminas"
echo "  - Directories: bakap-backup → terminas-backup"
echo "  - Config files: /etc/bakap-* → /etc/terminas-*"
echo "  - Service names: bakap-monitor → terminas-monitor"
echo "  - Log files: bakap-* → terminas-*"
echo "  - Credential paths: .bakap-credentials → .terminas-credentials"
echo "  - GitHub URLs: YiannisBourkelis/bakap → YiannisBourkelis/termiNAS"
echo ""
read -p "Continue? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Performing replacements..."

# Function to replace text in a file
replace_in_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "⚠️  File not found: $file"
        return
    fi
    
    # Backup original
    cp "$file" "$file.bak"
    
    # Perform replacements
    sed -i '' \
        -e 's|YiannisBourkelis/bakap|YiannisBourkelis/termiNAS|g' \
        -e 's|/opt/bakap|/opt/terminas|g' \
        -e 's|/usr/local/src/bakap|/usr/local/src/terminas|g' \
        -e 's|~/bakap|~/terminas|g' \
        -e 's|cd bakap|cd termiNAS|g' \
        -e 's|bakap-backup|terminas-backup|g' \
        -e 's|\.bakap-credentials|.terminas-credentials|g' \
        -e 's|/etc/bakap-|/etc/terminas-|g' \
        -e 's|bakap-monitor|terminas-monitor|g' \
        -e 's|/var/run/bakap|/var/run/terminas|g' \
        -e 's|99-bakap-inotify|99-terminas-inotify|g' \
        -e 's|/etc/logrotate.d/bakap-|/etc/logrotate.d/terminas-|g' \
        -e 's|/var/log/bakap-|/var/log/terminas-|g' \
        -e 's|bakap-web|terminas-web|g' \
        -e 's|bakap-sftp|terminas-sftp|g' \
        -e 's|bakap-samba|terminas-samba|g' \
        -e 's|bakap-sshd|terminas-sshd|g' \
        -e 's|nftables-bakap|nftables-terminas|g' \
        -e 's|filter.d/bakap-|filter.d/terminas-|g' \
        -e 's|jail.d/bakap-|jail.d/terminas-|g' \
        -e 's|action.d/nftables-bakap|action.d/nftables-terminas|g' \
        -e 's|BAKAP_|TERMINAS_|g' \
        -e 's|Bakap |termiNAS |g' \
        -e 's|bakap |termiNAS |g' \
        -e 's|the bakap |the termiNAS |g' \
        -e 's|to bakap |to termiNAS |g' \
        -e 's|C:\\\\bakap\\\\|C:\\\\termiNAS\\\\|g' \
        -e 's|C:\\bakap\\|C:\\termiNAS\\|g' \
        -e 's|%LOCALAPPDATA%\\bakap\\|%LOCALAPPDATA%\\terminas\\|g' \
        -e 's|AppData\\Local\\bakap\\|AppData\\Local\\terminas\\|g' \
        -e 's|ProgramData\\bakap-|ProgramData\\terminas-|g' \
        -e 's|Program Files\\bakap-|Program Files\\terminas-|g' \
        -e 's|Bakap-Backup-|termiNAS-Backup-|g' \
        -e 's|Bakap-Daily-Backup|termiNAS-Daily-Backup|g' \
        -e 's|Bakap Backup|termiNAS Backup|g' \
        -e 's|Bakap backup|termiNAS backup|g' \
        -e 's|Bakap Server|termiNAS Server|g' \
        -e 's|bakap server|termiNAS server|g' \
        -e 's|for bakap|for termiNAS|g' \
        -e 's|/tmp/bakap-|/tmp/terminas-|g' \
        -e 's|Bakap Project|termiNAS Project|g' \
        -e 's|bakap project|termiNAS project|g' \
        -e 's|# Bakap |# termiNAS |g' \
        -e 's|Bakap Monitor|termiNAS Monitor|g' \
        -e 's|Bakap real-time|termiNAS real-time|g' \
        -e 's|Bakap Retention|termiNAS Retention|g' \
        -e 's|Bakap fail2ban|termiNAS fail2ban|g' \
        -e 's|Bakap Samba|termiNAS Samba|g' \
        -e 's|Bakap custom|termiNAS custom|g' \
        -e 's|Bakap filter|termiNAS filter|g' \
        -e 's|Bakap Linux|termiNAS Linux|g' \
        -e 's|Bakap Windows|termiNAS Windows|g' \
        -e 's|Bakap Client|termiNAS Client|g' \
        -e 's|Bakap automated|termiNAS automated|g' \
        -e 's|\"Bakap |\"termiNAS |g' \
        -e "s|'Bakap |'termiNAS |g" \
        -e 's|Contributing to bakap|Contributing to termiNAS|g' \
        -e 's|to the bakap|to the termiNAS|g' \
        -e 's|# bakap|# termiNAS|g' \
        -e 's|on bakap|on termiNAS|g' \
        -e 's|Bakap is|termiNAS is|g' \
        -e 's|Bakap includes|termiNAS includes|g' \
        -e 's|Bakap supports|termiNAS supports|g' \
        -e 's|Bakap requires|termiNAS requires|g' \
        -e 's|Bakap User|termiNAS User|g' \
        -e "s|Bakap's|termiNAS's|g" \
        -e 's|\$bakapDataDir|\$terminasDataDir|g' \
        -e 's|path\\to\\bakap\\|path\\to\\termiNAS\\|g' \
        "$file"
    
    echo "✓ Updated: $file"
}

# Files to update
files=(
    "README.md"
    "PROJECT_REQUIREMENTS.md"
    "CONTRIBUTING.md"
    ".github/copilot-instructions.md"
    "src/server/setup.sh"
    "src/server/create_user.sh"
    "src/server/delete_user.sh"
    "src/server/manage_users.sh"
    "src/client/linux/upload.sh"
    "src/client/linux/setup-client.sh"
    "src/client/windows/upload.ps1"
    "src/client/windows/setup-client.ps1"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        replace_in_file "$file"
    else
        echo "⚠️  File not found: $file"
    fi
done

echo ""
echo "=================================================="
echo "✓ Renaming complete!"
echo "=================================================="
echo ""
echo "Backup files created with .bak extension"
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff"
echo "  2. Test the scripts in a VM"
echo "  3. If satisfied, commit: git add -A && git commit -m 'Rename bakap to termiNAS'"
echo "  4. Rename GitHub repo (see instructions below)"
echo ""
echo "To remove backup files:"
echo "  find . -name '*.bak' -delete"
echo ""
