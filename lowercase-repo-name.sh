#!/bin/bash
# lowercase-repo-name.sh - Update repository name from termiNAS to terminas
# This script updates all GitHub repository URLs to use lowercase 'terminas'
#
# Copyright (c) 2025 Yianni Bourkelis
# Licensed under the MIT License
#
# Usage: ./lowercase-repo-name.sh

set -e

echo "=========================================="
echo "termiNAS Repository Name Lowercase Update"
echo "=========================================="
echo ""
echo "This script will update all references from:"
echo "  YiannisBourkelis/termiNAS → YiannisBourkelis/terminas"
echo ""
echo "Files to be updated:"
echo "  - README.md"
echo "  - All server scripts (setup.sh, create_user.sh, etc.)"
echo "  - All client scripts (Linux and Windows)"
echo "  - Migration scripts (migrate-server.sh, migrate-paths.sh)"
echo "  - Documentation files"
echo "  - .github/copilot-instructions.md"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Updating files..."

# List of files to update
FILES=(
    "README.md"
    "src/server/setup.sh"
    "src/server/create_user.sh"
    "src/server/delete_user.sh"
    "src/server/manage_users.sh"
    "src/client/linux/setup-client.sh"
    "src/client/linux/upload.sh"
    "src/client/windows/setup-client.ps1"
    "src/client/windows/upload.ps1"
    "migrate-server.sh"
    "migrate-paths.sh"
    "rename-to-terminas.sh"
    "PATH_MIGRATION.md"
    "QUICK_SERVER_MIGRATION.md"
    ".github/copilot-instructions.md"
)

# Update each file
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        # Create backup
        cp "$file" "$file.bak"
        
        # Replace termiNAS with terminas in GitHub URLs
        sed -i '' 's|YiannisBourkelis/termiNAS|YiannisBourkelis/terminas|g' "$file"
        sed -i '' 's|github\.com/YiannisBourkelis/termiNAS|github.com/YiannisBourkelis/terminas|g' "$file"
        sed -i '' 's|githubusercontent\.com/YiannisBourkelis/termiNAS|githubusercontent.com/YiannisBourkelis/terminas|g' "$file"
        
        echo "  ✓ Updated: $file"
    else
        echo "  ⚠ Skipped (not found): $file"
    fi
done

echo ""
echo "=========================================="
echo "✓ Update Complete!"
echo "=========================================="
echo ""
echo "Backup files created with .bak extension"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Test that everything still works"
echo "  3. Rename GitHub repository: Settings → Repository name → 'terminas'"
echo "  4. Update local git remote: git remote set-url origin https://github.com/YiannisBourkelis/terminas.git"
echo "  5. Commit changes: git add -A && git commit -m 'Update repository name to lowercase'"
echo "  6. Push: git push origin main"
echo ""
echo "To remove backup files: find . -name '*.bak' -delete"
echo ""
