# GitHub Repository Renaming Guide

## Step 1: Rename Your GitHub Repository

1. **Navigate to your repository on GitHub:**
   - Go to https://github.com/YiannisBourkelis/bakap

2. **Open Settings:**
   - Click the **Settings** tab (⚙️ icon in the top navigation)

3. **Rename the repository:**
   - Scroll down to the **"Repository name"** section (near the top of the settings page)
   - Change `bakap` to `termiNAS`
   - Click the **"Rename"** button
   - GitHub will warn you about redirects — click **"I understand, update my repository"**

4. **GitHub automatically handles:**
   - ✅ Permanent redirects from `bakap` → `termiNAS`
   - ✅ All `git clone`, `git fetch`, `git push` operations
   - ✅ Web traffic (issues, pull requests, wiki, etc.)
   - ✅ Your new repository URL: `https://github.com/YiannisBourkelis/termiNAS`

## Step 2: Update Your Local Development Repository

```bash
cd /Users/yiannis/Projects/bakap

# Update remote URL to new name
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git

# Verify the change
git remote -v
```

**Expected output:**
```
origin  https://github.com/YiannisBourkelis/termiNAS.git (fetch)
origin  https://github.com/YiannisBourkelis/termiNAS.git (push)
```

## Step 3: Rename Your Local Directory (Optional)

```bash
cd /Users/yiannis/Projects
mv bakap termiNAS
cd termiNAS
```

## Step 4: Commit and Push All Changes

```bash
cd /Users/yiannis/Projects/termiNAS

# Remove backup files created by renaming script
find . -name '*.bak' -delete

# Review all changes
git status
git diff

# Add all changes
git add -A

# Commit with descriptive message
git commit -m "Rename project from bakap to termiNAS

Breaking changes:
- Project name: bakap → termiNAS
- GitHub URL: YiannisBourkelis/bakap → YiannisBourkelis/termiNAS
- Installation paths: /opt/bakap → /opt/terminas
- Service names: bakap-monitor → terminas-monitor
- Config files: /etc/bakap-* → /etc/terminas-*
- Log files: /var/log/bakap-* → /var/log/terminas-*
- Client directories: bakap-backup → terminas-backup
- Credentials: .bakap-credentials → .terminas-credentials
- Environment variables: BAKAP_* → TERMINAS_*

This is a breaking change for existing installations.
See MIGRATION.md for upgrade instructions."

# Push to GitHub
git push origin main
```

## Step 5: Verify GitHub Rename

After pushing, visit your repository:
- New URL: https://github.com/YiannisBourkelis/termiNAS
- Old URL: https://github.com/YiannisBourkelis/bakap (should redirect)

## Step 6: Update Any Existing Server Installations

For any servers that already have bakap installed:

```bash
# SSH into your backup server
ssh your-server

# Update git remote URL
cd /opt/bakap  # or wherever it's installed
sudo git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git

# Verify
sudo git remote -v
```

**Note:** The installation will still work with old paths (`/opt/bakap`), but future installations will use `/opt/terminas`. Existing installations don't need to be migrated immediately.

## Important Notes

### For Existing Users

GitHub redirects will ensure:
- ✅ `git clone https://github.com/YiannisBourkelis/bakap.git` → redirects to termiNAS
- ✅ Existing clones can still push/pull (redirects work transparently)
- ✅ All existing links, issues, PRs remain accessible

However, users should update their:
- Git remote URLs
- Documentation that references the old repo
- Bookmarks and links

### Breaking Changes for Installations

This rename introduces breaking changes for the **next version** of termiNAS. Existing bakap installations will continue to work, but new installations will use:

- `/opt/terminas` instead of `/opt/bakap`
- `terminas-monitor.service` instead of `bakap-monitor.service`
- `/etc/terminas-retention.conf` instead of `/etc/bakap-retention.conf`
- And all other path changes listed above

### Migration Path

Since bakap is currently in **alpha/experimental** stage, we recommend:

**Option 1: Clean Install (Recommended)**
- Backup your data
- Uninstall bakap completely
- Install fresh termiNAS installation

**Option 2: Wait for Migration Script**
- A future release will include `migrate-bakap-to-terminas.sh`
- This will safely migrate paths and configurations

## Timeline

1. ✅ **Now**: Update all project files (completed by rename script)
2. ✅ **Now**: Commit changes to git
3. ⏳ **Next**: Rename GitHub repository
4. ⏳ **Next**: Push changes to GitHub
5. ⏳ **Later**: Update local dev directory name (optional)
6. ⏳ **Future**: Create migration script for existing installations

## Need Help?

If you encounter issues during the rename:
- Check GitHub's repository renaming docs: https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository
- Verify redirects are working: visit old URL and confirm redirect
- Check git remotes: `git remote -v`

---

**Congratulations!** Your project is now **termiNAS** 🎉
