# GitHub Repository Lowercase Rename Guide

## Overview
This guide walks you through renaming the GitHub repository from `termiNAS` (mixed case) to `terminas` (all lowercase) while keeping the project display name as "termiNAS".

## Why Lowercase?
- **Consistency**: When users clone the repo, the directory name will be `terminas` (predictable, no case confusion)
- **Convention**: Most GitHub repositories use lowercase names
- **Simplicity**: Easier to type and remember
- **URLs**: GitHub URLs are case-insensitive but lowercase is cleaner

## Before You Start

### Step 1: Update All Code References
Run the provided script to update all GitHub URLs in the codebase:

```bash
cd /Users/yiannis/Projects/termiNAS
./lowercase-repo-name.sh
```

This will update all references from `YiannisBourkelis/termiNAS` → `YiannisBourkelis/terminas` in:
- All server scripts
- All client scripts
- Documentation files
- Migration scripts

### Step 2: Review Changes
```bash
git diff
```

Verify that only GitHub URLs were changed (not the project display name "termiNAS").

### Step 3: Commit Changes (but don't push yet)
```bash
git add -A
git commit -m "Update repository name to lowercase (terminas)"
```

**Note**: Don't push yet! We need to rename the GitHub repository first.

## Rename GitHub Repository

### Step 4: Rename on GitHub
1. Go to https://github.com/YiannisBourkelis/termiNAS
2. Click **Settings** (top right)
3. Scroll down to **Repository name**
4. Change `termiNAS` to `terminas` (all lowercase)
5. Click **Rename**

GitHub will automatically:
- ✅ Set up redirects from old URL to new URL
- ✅ Update all forks
- ✅ Preserve stars, watchers, issues, PRs
- ✅ Keep all git history intact

### Step 5: Update Your Local Git Remote
```bash
cd /Users/yiannis/Projects/termiNAS

# Update remote URL
git remote set-url origin https://github.com/YiannisBourkelis/terminas.git

# Verify
git remote -v
# Should show: https://github.com/YiannisBourkelis/terminas.git
```

### Step 6: Push Your Changes
```bash
git push origin main
```

### Step 7: Rename Your Local Directory (Optional)
```bash
cd /Users/yiannis/Projects
mv termiNAS terminas
cd terminas
```

Now your local directory name matches the repository name!

## Update Repository Display Settings

### Step 8: Keep "termiNAS" as Display Name
Even though the repo URL is lowercase, you can keep the branding:

1. Go to https://github.com/YiannisBourkelis/terminas
2. Click **Settings**
3. In **Repository name** section, the URL slug is `terminas` (lowercase)
4. In **About** section (main repo page), set:
   - **Description**: Your existing description with "termiNAS" (capitalized)
   - **Website**: Your project website
   - **Topics**: Your existing topics

The repository will be accessible at `github.com/YiannisBourkelis/terminas` but the display name in the About section can still show "termiNAS".

## What About Old Links?

### GitHub's Automatic Redirects
GitHub automatically redirects:
- `github.com/YiannisBourkelis/termiNAS` → `github.com/YiannisBourkelis/terminas`
- Old clone URLs still work
- Existing forks update automatically
- Stars, watchers, issues preserved

### Users Won't Be Affected
- **Existing clones**: Continue to work (git uses remote URL which GitHub redirects)
- **Documentation with old URLs**: Still work thanks to GitHub redirects
- **GitHub badges/shields**: Update automatically to new URL

## Testing After Rename

### Verify Everything Works
```bash
# Clone from new URL (in a temp directory)
cd /tmp
git clone https://github.com/YiannisBourkelis/terminas.git
cd terminas

# Directory name should be lowercase
pwd
# Should show: /tmp/terminas

# Check that all URLs in files are updated
grep -r "YiannisBourkelis/termiNAS" .
# Should return no matches (except in this guide and changelog)
```

## Cleanup

### Remove Backup Files
```bash
cd /Users/yiannis/Projects/terminas
find . -name '*.bak' -delete
```

### Update VS Code Workspace (if needed)
If you use VS Code workspace files, update the folder path:
```json
{
  "folders": [
    {
      "path": "/Users/yiannis/Projects/terminas"
    }
  ]
}
```

## Summary

### What Changed
- ✅ Repository URL: `github.com/YiannisBourkelis/terminas` (lowercase)
- ✅ Clone directory name: `terminas` (lowercase)
- ✅ All code references updated to lowercase
- ✅ Git remotes updated

### What Stayed the Same
- ✅ Project display name: "termiNAS" (in README, About section, etc.)
- ✅ All git history
- ✅ Stars, watchers, issues, PRs
- ✅ Existing clones work (thanks to GitHub redirects)

## Troubleshooting

### "Repository not found" error
- Wait a few minutes after renaming (GitHub needs to update redirects)
- Verify you're using the correct URL: `https://github.com/YiannisBourkelis/terminas.git`

### Old remote URL still showing
```bash
git remote set-url origin https://github.com/YiannisBourkelis/terminas.git
```

### Local directory still has old name
```bash
cd /Users/yiannis/Projects
mv termiNAS terminas
```

## Done!
Your repository is now accessible at `github.com/YiannisBourkelis/terminas` with consistent lowercase naming, while the project display name remains "termiNAS" for branding. 🎉

---

*Created: October 18, 2025*
