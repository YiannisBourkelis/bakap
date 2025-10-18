# Complete Guide: Renaming Your GitHub Repository

## 🎯 Quick Overview

You're about to rename your GitHub repository from `bakap` to `termiNAS`. This guide walks you through every step.

**Time required:** ~10 minutes  
**Difficulty:** Easy  
**Reversible:** Yes (can rename back if needed)

---

## 📋 Pre-Flight Checklist

Before you start, make sure:
- [ ] You're logged into GitHub
- [ ] You have admin access to the repository
- [ ] All your local changes are committed
- [ ] You've reviewed the changes in your project files

---

## 🚀 Step-by-Step Instructions

### Step 1: Commit Your Local Changes

```bash
cd /Users/yiannis/Projects/bakap

# Check what files were changed
git status

# Review the changes
git diff

# Add all changes
git add -A

# Commit with a clear message
git commit -m "Rename project from bakap to termiNAS

Breaking changes:
- Project name: bakap → termiNAS
- GitHub URL: YiannisBourkelis/bakap → YiannisBourkelis/termiNAS
- Installation paths: /opt/bakap → /opt/terminas
- Service names: bakap-monitor → terminas-monitor
- Config files: /etc/bakap-* → /etc/terminas-*
- Log files: bakap-* → terminas-*
- Environment variables: BAKAP_* → TERMINAS_*

This is a breaking change for existing installations.
See MIGRATION.md for upgrade instructions."

# Verify commit
git log -1
```

### Step 2: Rename GitHub Repository

**Via Web Browser:**

1. Open your browser and go to:
   ```
   https://github.com/YiannisBourkelis/bakap
   ```

2. Click the **"Settings"** tab (⚙️ icon at the top of the page)

3. Scroll down to find the **"Repository name"** section (near the top)

4. In the text field, change `bakap` to `termiNAS`

5. Click the **"Rename"** button

6. GitHub will show you a warning dialog:
   - ✅ It explains that redirects will be set up
   - ✅ It lists what will change
   - ✅ Read it and click **"I understand, rename my repository"**

7. **Success!** Your repository is now at:
   ```
   https://github.com/YiannisBourkelis/termiNAS
   ```

**What GitHub Does Automatically:**
- ✅ Creates permanent HTTP redirects from old URL → new URL
- ✅ Redirects all `git clone`, `git fetch`, `git push` operations
- ✅ Redirects web browser visits
- ✅ Updates links in issues, pull requests, and wikis
- ✅ Preserves all stars, forks, and watchers

### Step 3: Update Your Local Git Remote

```bash
cd /Users/yiannis/Projects/bakap

# Update the remote URL to the new repository name
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git

# Verify it worked
git remote -v
```

**Expected output:**
```
origin  https://github.com/YiannisBourkelis/termiNAS.git (fetch)
origin  https://github.com/YiannisBourkelis/termiNAS.git (push)
```

### Step 4: Push Your Changes

```bash
# Push the renamed project to GitHub
git push origin main
```

**What happens:**
- ✅ Your commits are pushed to the renamed repository
- ✅ GitHub shows the new `termiNAS` name everywhere
- ✅ All files reflect the new naming

### Step 5: Rename Your Local Directory (Optional)

```bash
# Go up one directory
cd /Users/yiannis/Projects

# Rename the local folder
mv bakap termiNAS

# Go back into the renamed directory
cd termiNAS

# Verify everything still works
git status
```

### Step 6: Verify Everything Works

Test that the renaming was successful:

```bash
cd /Users/yiannis/Projects/termiNAS

# Pull from GitHub (should work with new URL)
git pull origin main

# Check remote URLs
git remote -v

# Visit the repository in your browser
open https://github.com/YiannisBourkelis/termiNAS
```

---

## ✅ Verification Checklist

After completing all steps, verify:

- [ ] GitHub repository shows new name: `termiNAS`
- [ ] Old URL redirects: https://github.com/YiannisBourkelis/bakap → termiNAS
- [ ] Local git remote shows new URL
- [ ] `git pull` works without errors
- [ ] `git push` works without errors
- [ ] Local directory renamed (if you did Step 5)
- [ ] All project files reference `termiNAS` (not `bakap`)
- [ ] README.md shows `# termiNAS` as the title

---

## 🔄 What About Existing Clones?

**Good news:** GitHub's redirects mean existing clones will continue to work!

Anyone who previously cloned `bakap` can:
- Continue pushing/pulling (redirects work transparently)
- But should update their remote URL eventually:

```bash
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
```

---

## 📢 Communicating the Change

### Update Your README

Add this notice at the top of your README.md:

```markdown
> **🔔 Project Renamed: bakap → termiNAS**
>
> This project was renamed from "bakap" to "termiNAS" to better reflect its purpose as a terminal-based NAS with immutable Btrfs snapshots.
>
> - **Old URL:** https://github.com/YiannisBourkelis/bakap (redirects automatically)
> - **New URL:** https://github.com/YiannisBourkelis/termiNAS
> - **For existing installations:** See [MIGRATION.md](MIGRATION.md) for upgrade instructions
```

### Create a GitHub Release

Consider creating a release announcement:

1. Go to your repository → **Releases** → **Create a new release**
2. Tag: `v1.0.0` (or `v0.2.0` if staying in alpha)
3. Title: `🎉 Project Renamed: termiNAS v1.0.0`
4. Description:
   ```markdown
   # termiNAS - Formerly "bakap"
   
   ## Major Changes
   
   - **Project renamed** from "bakap" to "termiNAS"
   - Better name that communicates purpose: **termi**nal-based **NAS**
   - All paths and configurations updated
   
   ## Breaking Changes
   
   This is a breaking change for existing bakap installations:
   - Installation paths: `/opt/bakap` → `/opt/terminas`
   - Service names: `bakap-monitor` → `terminas-monitor`
   - Configuration files: `/etc/bakap-*` → `/etc/terminas-*`
   
   See [MIGRATION.md](MIGRATION.md) for upgrade instructions.
   
   ## For New Users
   
   Simply clone and install:
   ```bash
   git clone https://github.com/YiannisBourkelis/termiNAS.git
   cd termiNAS
   sudo ./src/server/setup.sh
   ```
   
   ## Documentation
   
   - [README.md](README.md) - Complete documentation
   - [MIGRATION.md](MIGRATION.md) - Upgrade from bakap
   - [GITHUB_RENAME_GUIDE.md](GITHUB_RENAME_GUIDE.md) - Repository renaming guide
   ```

---

## 🆘 Troubleshooting

### Problem: "git push" says "Permission denied"

**Solution:**
```bash
# Verify your remote URL
git remote -v

# If it still shows old URL, update it:
git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git

# Try again
git push origin main
```

### Problem: Old GitHub URL doesn't redirect

**Solution:**
- Wait a few minutes - redirects may take time to propagate
- Clear your browser cache
- Try in an incognito/private window
- If still not working, double-check the repository was actually renamed in Settings

### Problem: Getting 404 on new repository URL

**Solution:**
- Double-check spelling: `termiNAS` (capital N, capital A, capital S)
- Ensure you clicked "Rename" and confirmed in GitHub Settings
- Check your repository list: https://github.com/YiannisBourkelis?tab=repositories

---

## 🎉 Success!

If you've completed all steps, congratulations! Your project is now **termiNAS**.

### Next Steps

1. **Test in a VM:**
   - Clone the renamed repository
   - Run `sudo ./src/server/setup.sh`
   - Verify everything works

2. **Update any bookmarks:**
   - Browser bookmarks
   - Documentation links
   - Wiki pages (if any)

3. **Notify collaborators (if any):**
   - Let them know about the name change
   - Share the migration guide
   - Update any shared documentation

4. **Update any servers with bakap installed:**
   ```bash
   ssh your-server
   cd /opt/bakap  # or wherever installed
   sudo git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
   ```

---

## 📚 Additional Resources

- **Migration Guide:** See `MIGRATION.md` for migrating existing bakap installations
- **Full Rename Guide:** See `GITHUB_RENAME_GUIDE.md` for more details
- **Rename Summary:** See `RENAMING_SUMMARY.md` for a summary of all changes
- **GitHub Docs:** https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository

---

## 🤔 Need Help?

If you run into any issues:
1. Check the troubleshooting section above
2. Review `GITHUB_RENAME_GUIDE.md` for detailed instructions
3. Check GitHub's official documentation
4. Create a GitHub issue (on the new repository URL)

---

**You did it!** 🎊 Your project is now **termiNAS** - a much clearer name that communicates exactly what it does!
