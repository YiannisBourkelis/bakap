#!/bin/bash
# migrate_to_explicit_includes.sh - Migrate existing Samba config to use explicit includes
#
# This script updates an existing bakap server to use explicit includes instead of
# wildcard includes or direct appends. Run this on servers already using the old approach.
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License - see LICENSE file for details

set -e

echo "=========================================="
echo "Migrating to Explicit Includes"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Check if Samba is configured
if [ ! -f /etc/samba/smb.conf ]; then
    echo "Error: Samba is not configured (smb.conf not found)" >&2
    exit 1
fi

echo "Step 1: Backup current configuration"
echo "-------------------------------------"
cp /etc/samba/smb.conf /etc/samba/smb.conf.pre-migration
echo "✓ Backed up to smb.conf.pre-migration"
echo ""

echo "Step 2: Remove old share definitions from main config"
echo "------------------------------------------------------"
# Remove all user share sections (between [username-backup] and next section or EOF)
# Keep only the [global] section
sed -i '/^\[.*-backup\]/,/^\[/d' /etc/samba/smb.conf
sed -i '/^\[.*-versions\]/,/^\[/d' /etc/samba/smb.conf
# Also remove the note about appending
sed -i '/# Note: User shares are appended/d' /etc/samba/smb.conf
sed -i '/# Note: Per-user config files/d' /etc/samba/smb.conf
sed -i '/# To add new users: run create_user.sh/d' /etc/samba/smb.conf
sed -i '/# and appends them to this main config/d' /etc/samba/smb.conf
echo "✓ Removed old share definitions"
echo ""

echo "Step 3: Remove old include lines (wildcards)"
echo "---------------------------------------------"
sed -i '/^include = .*\*\.conf/d' /etc/samba/smb.conf
sed -i '/^config include = .*\*\.conf/d' /etc/samba/smb.conf
echo "✓ Removed wildcard includes"
echo ""

echo "Step 4: Add explicit includes"
echo "------------------------------"
# Add explicit includes before any remaining share sections or at end
if grep -q '^\[' /etc/samba/smb.conf; then
    # Find first share section
    FIRST_SHARE=$(grep -n '^\[' /etc/samba/smb.conf | grep -v '^\[global\]' | head -1 | cut -d: -f1)
    if [ -n "$FIRST_SHARE" ]; then
        # Insert before first share
        {
            head -n $((FIRST_SHARE - 1)) /etc/samba/smb.conf
            echo ""
            echo "# Explicit includes for per-user configurations"
            for conf in /etc/samba/smb.conf.d/*.conf; do
                [ -f "$conf" ] && echo "include = $conf"
            done
            echo ""
            tail -n +${FIRST_SHARE} /etc/samba/smb.conf
        } > /etc/samba/smb.conf.tmp
        mv /etc/samba/smb.conf.tmp /etc/samba/smb.conf
    fi
else
    # No shares, append at end
    echo "" >> /etc/samba/smb.conf
    echo "# Explicit includes for per-user configurations" >> /etc/samba/smb.conf
    for conf in /etc/samba/smb.conf.d/*.conf; do
        [ -f "$conf" ] && echo "include = $conf"
    done
fi

# Count includes added
INCLUDE_COUNT=$(grep -c '^include = /etc/samba/smb.conf.d/.*\.conf' /etc/samba/smb.conf || echo 0)
echo "✓ Added $INCLUDE_COUNT explicit includes"
echo ""

echo "Step 5: Add note about include management"
echo "------------------------------------------"
cat >> /etc/samba/smb.conf <<'EOF'

# Note: Per-user config files in /etc/samba/smb.conf.d/ are included above
# To add new users: run create_user.sh or manage_users.sh enable-samba
# The include list is automatically updated when users are added/removed
EOF
echo "✓ Added note"
echo ""

echo "Step 6: Validate configuration"
echo "-------------------------------"
if testparm -s /etc/samba/smb.conf > /dev/null 2>&1; then
    echo "✓ Configuration is valid"
else
    echo "✗ Configuration has errors!"
    echo "  Run: testparm -s /etc/samba/smb.conf"
    echo ""
    echo "  To restore backup:"
    echo "  cp /etc/samba/smb.conf.pre-migration /etc/samba/smb.conf"
    exit 1
fi
echo ""

echo "Step 7: Show what will be loaded"
echo "---------------------------------"
echo "Shares that will be loaded:"
testparm -s /etc/samba/smb.conf 2>/dev/null | grep '^\[' | grep -v '^\[global\]'
echo ""

echo "Step 8: Restart Samba"
echo "---------------------"
systemctl restart smbd nmbd
echo "✓ Samba restarted"
echo ""

echo "=========================================="
echo "Migration Complete!"
echo "=========================================="
echo ""
echo "Your Samba configuration now uses explicit includes."
echo "Per-user config files in /etc/samba/smb.conf.d/ are actively loaded."
echo ""
echo "Next steps:"
echo "1. Test share access from clients"
echo "2. If everything works, you can remove the backup:"
echo "   rm /etc/samba/smb.conf.pre-migration"
echo ""
echo "If you encounter issues:"
echo "1. Restore backup: cp /etc/samba/smb.conf.pre-migration /etc/samba/smb.conf"
echo "2. Restart Samba: systemctl restart smbd nmbd"
echo ""
