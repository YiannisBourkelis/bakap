# Renaming Summary: bakap → termiNAS

## ✅ Completed Changes

All project files have been successfully renamed from **bakap** to **termiNAS**.

### Files Modified (12 files)

1. **Documentation:**
   - `README.md` - Main project documentation
   - `PROJECT_REQUIREMENTS.md` - Project requirements
   - `CONTRIBUTING.md` - Contribution guidelines
   - `.github/copilot-instructions.md` - AI assistant instructions

2. **Server Scripts:**
   - `src/server/setup.sh` - Main setup script
   - `src/server/create_user.sh` - User creation
   - `src/server/delete_user.sh` - User deletion
   - `src/server/manage_users.sh` - User management

3. **Client Scripts:**
   - `src/client/linux/upload.sh` - Linux upload client
   - `src/client/linux/setup-client.sh` - Linux automated setup
   - `src/client/windows/upload.ps1` - Windows upload client
   - `src/client/windows/setup-client.ps1` - Windows automated setup

### New Files Created (3 files)

1. `GITHUB_RENAME_GUIDE.md` - Step-by-step guide for renaming GitHub repository
2. `MIGRATION.md` - Migration guide for existing bakap installations
3. `rename-to-terminas.sh` - Automated renaming script (can be deleted after use)

### Key Changes Made

#### Path Changes
- `/opt/bakap` → `/opt/terminas`
- `/usr/local/bin/bakap-backup` → `/usr/local/bin/terminas-backup`
- `/root/.bakap-credentials` → `/root/.terminas-credentials`
- `C:\Program Files\bakap-backup` → `C:\Program Files\terminas-backup`
- `C:\ProgramData\bakap-credentials` → `C:\ProgramData\terminas-credentials`
- `C:\ProgramData\bakap-logs` → `C:\ProgramData\terminas-logs`

#### Service & Configuration Changes
- `bakap-monitor.service` → `terminas-monitor.service`
- `/etc/bakap-retention.conf` → `/etc/terminas-retention.conf`
- `/var/run/bakap` → `/var/run/terminas`
- `/var/log/bakap-*` → `/var/log/terminas-*`
- `/etc/logrotate.d/bakap-*` → `/etc/logrotate.d/terminas-*`

#### fail2ban Changes
- `bakap-sshd` → `terminas-sshd`
- `bakap-samba` → `terminas-samba`
- `bakap-sftp` → `terminas-sftp`
- `/etc/fail2ban/jail.d/bakap-*` → `/etc/fail2ban/jail.d/terminas-*`
- `/etc/fail2ban/filter.d/bakap-*` → `/etc/fail2ban/filter.d/terminas-*`
- `nftables-bakap` → `nftables-terminas`

#### Environment Variables
- `BAKAP_INACTIVITY_WINDOW` → `TERMINAS_INACTIVITY_WINDOW`
- `BAKAP_SNAPSHOT_INTERVAL` → `TERMINAS_SNAPSHOT_INTERVAL`
- `BAKAP_MAX_WAIT` → `TERMINAS_MAX_WAIT`

#### Repository Changes
- GitHub URL: `YiannisBourkelis/bakap` → `YiannisBourkelis/termiNAS`
- Clone command: Updated to new repo name
- All documentation links: Updated to new URL

## 📋 Next Steps

### Immediate Actions (Do Now)

1. **Review the changes:**
   ```bash
   cd /Users/yiannis/Projects/bakap
   git diff
   ```

2. **Commit the changes:**
   ```bash
   git add -A
   git commit -m "Rename project from bakap to termiNAS

   Breaking changes:
   - Project name: bakap → termiNAS  
   - GitHub URL: YiannisBourkelis/bakap → YiannisBourkelis/termiNAS
   - Installation paths: /opt/bakap → /opt/terminas
   - Service names: bakap-monitor → terminas-monitor
   - Config files: /etc/bakap-* → /etc/terminas-*
   - Environment variables: BAKAP_* → TERMINAS_*
   
   See MIGRATION.md for upgrade instructions for existing installations."
   ```

3. **Rename your GitHub repository:**
   - Follow the step-by-step guide in `GITHUB_RENAME_GUIDE.md`
   - Go to https://github.com/YiannisBourkelis/bakap/settings
   - Change repository name from `bakap` to `termiNAS`
   - Click "Rename"

4. **Push the changes:**
   ```bash
   git push origin main
   ```

5. **Update your local git remote:**
   ```bash
   git remote set-url origin https://github.com/YiannisBourkelis/termiNAS.git
   git remote -v
   ```

6. **Rename your local directory (optional):**
   ```bash
   cd /Users/yiannis/Projects
   mv bakap termiNAS
   cd termiNAS
   ```

### Later Actions (When Convenient)

1. **Test in a VM:**
   - Clone the renamed repository
   - Run setup script
   - Verify all functionality works

2. **Update any server installations:**
   - SSH into servers with bakap installed
   - Update git remote URL
   - Either keep old installation or migrate (see `MIGRATION.md`)

3. **Notify users (if any):**
   - Update documentation or wiki
   - Post announcement about name change
   - Provide migration guide link

## 🔍 Verification Checklist

Before pushing to GitHub, verify:

- [ ] All files compile/run without errors
- [ ] No references to "bakap" in user-facing documentation (except migration guide)
- [ ] GitHub URLs updated throughout project
- [ ] Installation paths updated in README
- [ ] Service names updated in documentation
- [ ] Environment variable names updated
- [ ] Client script paths updated
- [ ] Copyright headers intact (year: 2025, author: Yianni Bourkelis)
- [ ] MIT License unchanged

## 📝 Breaking Changes Notice

This is a **major breaking change** for existing installations. The next release should be:
- Version: `1.0.0` (major version bump)
- Or: `0.2.0` (if staying in alpha)

Add this to your README near the top:

```markdown
> **🔔 Project Renamed: bakap → termiNAS**
>
> This project was previously named "bakap" and has been renamed to "termiNAS" to better reflect its purpose as a terminal-based Network Attached Storage solution with immutable snapshots.
>
> - Old GitHub URL: https://github.com/YiannisBourkelis/bakap (redirects automatically)
> - New GitHub URL: https://github.com/YiannisBourkelis/termiNAS
> - For existing bakap installations, see [MIGRATION.md](MIGRATION.md)
```

## 🛠️ Files You Can Delete (After Successful Push)

Once everything is committed and pushed successfully:

```bash
# Delete the renaming script (no longer needed)
rm rename-to-terminas.sh
```

## 📚 Documentation Files to Review

Make sure users can find these important documents:

- `README.md` - Main documentation (updated ✓)
- `GITHUB_RENAME_GUIDE.md` - How to rename GitHub repo (new ✓)
- `MIGRATION.md` - Migration guide for existing users (new ✓)
- `CONTRIBUTING.md` - Updated with new project name (updated ✓)
- `PROJECT_REQUIREMENTS.md` - Updated requirements (updated ✓)

## 🎉 Congratulations!

Your project has been successfully renamed from **bakap** to **termiNAS**!

The new name better communicates:
- **termi** = Terminal/CLI-based (no GUI)
- **NAS** = Network Attached Storage
- Implies: Professional, server-side, backup/storage solution

All that's left is to:
1. Commit the changes
2. Rename the GitHub repository  
3. Push to GitHub
4. Celebrate! 🎊

---

**Questions or issues?** Check `GITHUB_RENAME_GUIDE.md` for detailed instructions.
