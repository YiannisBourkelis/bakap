# termiNAS Project - Custom Instructions

## Project Overview

termiNAS is a secure, versioned backup server for Debian Linux that provides ransomware protection through real-time incremental snapshots. The system allows remote clients (Windows/Linux) to upload files via SFTP, with server-side automatic versioning that prevents client-side malware from corrupting or deleting backup history.

**Key Principle**: Server-side immutability - clients can upload files, but cannot modify or delete version history stored in root-owned snapshots.

## Project Goals

### Primary Objectives
1. **Ransomware Protection**: Ensure backup versions remain intact even if client machines are compromised
2. **Real-time Versioning**: Automatically snapshot file changes as they occur using inotify monitoring
3. **Secure Access Control**: Strict chroot SFTP-only access with fail2ban protection
4. **Efficient Storage**: Use hardlinks for incremental backups to minimize disk usage
5. **Easy Setup**: Automated configuration scripts for both server and clients

### Security Requirements
- Users chrooted to home directories (cannot access other parts of filesystem)
- Version snapshots owned by root (users can read but not modify)
- fail2ban protection against brute force attacks and DOS
- SSH/SFTP only (no shell access for backup users)
- 64-character secure passwords by default

### User Experience Goals
- One-command server setup (`setup.sh`)
- One-command user creation (`create_user.sh <username>`)
- Interactive client setup wizards (Linux: `setup-client.sh`, Windows: `setup-client.ps1`)
- Comprehensive management tools (`manage_users.sh` with 9 commands)
- Clear documentation with troubleshooting guides

## Folder Structure

```
terminas/
├── LICENSE                      # MIT License
├── CONTRIBUTING.md              # Contribution guidelines with CLA
├── README.md                    # Complete project documentation
├── PROJECT_REQUIREMENTS.md      # Original requirements and scope
├── .cursorrules                 # This file - project instructions
└── src/
    ├── server/                  # Server-side scripts (Debian)
    │   ├── setup.sh            # Main server installation & configuration
    │   ├── create_user.sh      # Create backup users with secure passwords
    │   ├── delete_user.sh      # Remove backup users and their data
    │   └── manage_users.sh     # User/snapshot management (list, info, history, etc.)
    └── client/                  # Client-side scripts
        ├── linux/               # Linux/Unix clients
        │   ├── setup-client.sh # Interactive automated backup setup
        │   └── upload.sh       # Manual upload with hash checking
        └── windows/             # Windows clients (PowerShell)
            ├── setup-client.ps1 # Interactive automated backup setup
            └── upload.ps1      # Manual upload with hash checking

Server Runtime Files (created by setup.sh):
/var/backups/scripts/
├── monitor_backups.sh          # inotify-based real-time snapshot monitor
└── cleanup_snapshots.sh        # Retention policy enforcement

/etc/
├── terminas-retention.conf        # Retention policy configuration
└── systemd/system/
    └── terminas-monitor.service   # systemd service for monitoring

/home/<username>/               # Per-user backup structure
├── uploads/                    # Writable upload directory (user:backupusers, 700)
└── versions/                   # Read-only snapshots (root:backupusers, 755)
    ├── YYYY-MM-DD_HH-MM-SS/   # Timestamped snapshots
    └── ...

Client Runtime Files:
Linux: /usr/local/bin/terminas-backup/, /root/.terminas-credentials/, /var/log/
Windows: C:\Program Files\terminas-backup\, C:\ProgramData\terminas-credentials\, C:\ProgramData\terminas-logs\
```

## Tools and Technologies

### Server-Side (Debian Linux)
- **Bash 4.x+**: All server scripts
- **OpenSSH**: SFTP with chroot configuration
- **inotify-tools**: Real-time filesystem monitoring (`inotifywait`)
- **rsync**: Incremental snapshots with `--link-dest` for hardlinks
- **fail2ban**: SSH/SFTP brute force and DOS protection
- **iptables**: Firewall-level IP blocking (via fail2ban)
- **systemd**: Service management (`terminas-monitor.service`)
- **cron**: Scheduled retention policy cleanup
- **pwgen**: Secure 64-character password generation
- **getent/groupadd/useradd**: User and group management

### Client-Side
**Linux/Unix:**
- **Bash 4.x+**: Client scripts
- **lftp** (preferred) or **sftp**: SFTP file transfer
- **sha256sum**: Hash-based change detection
- **cron**: Scheduled automated backups
- **logrotate**: Log management

**Windows (Server 2008 R2+):**
- **PowerShell 2.0+**: All Windows scripts
- **WinSCP** (preferred) or **PuTTY (pscp.exe)**: SFTP file transfer
- **Task Scheduler**: Automated backup scheduling
- **.NET Framework**: SHA-256 hashing, secure credential storage

### Version Control & Collaboration
- **Git**: Source control and client auto-updates
- **GitHub**: Repository hosting at YiannisBourkelis/terminas
- **Markdown**: Documentation format

## Architecture and Design Patterns

### Security Architecture
1. **Defense in Depth**:
   - Network layer: fail2ban blocks malicious IPs at iptables level
   - Authentication layer: SSH with strong passwords or keys
   - Authorization layer: Chroot prevents filesystem access outside home
   - Data layer: Root-owned snapshots prevent client modification

2. **Principle of Least Privilege**:
   - Backup users: SFTP-only, chrooted, nologin shell
   - Monitor service: Runs as root but only writes to versions directories
   - Client credentials: Stored with restrictive permissions (600 Linux, Administrators-only Windows)

### Snapshot Strategy
- **Trigger**: inotify events (`close_write`, `moved_to`) - captures complete files only
- **Method**: rsync with `--link-dest` pointing to previous snapshot
- **Timing**: Debounce period (default 10s) to coalesce rapid changes
- **Storage**: Hardlinks for unchanged files = space-efficient versioning
- **Ownership**: root:backupusers with 755 (readable by user, immutable)

### Retention Policy
**Grandfather-Father-Son (default)**:
- Daily: Keep last 7 days
- Weekly: Keep last 4 weeks (one snapshot per week)
- Monthly: Keep last 6 months (one snapshot per month)

**Simple Age-Based (alternative)**:
- Keep snapshots for N days, delete older

**Per-User Overrides**: Configurable in `/etc/terminas-retention.conf`

## Development Guidelines

### Code Style
**Bash Scripts**:
- Use `#!/usr/bin/env bash` shebang
- Enable strict mode: `set -euo pipefail` (except where specific handling needed)
- Use functions for modularity
- Quote all variable expansions: `"$variable"`
- Use `[[` for conditionals instead of `[`
- Validate inputs and check command exit codes
- Add descriptive comments for complex logic

**PowerShell Scripts**:
- Use `[CmdletBinding()]` for advanced function features
- Set `$ErrorActionPreference = "Stop"` for critical operations
- Use proper parameter validation (`[Parameter(Mandatory=$true)]`)
- Use `Try-Catch` for error handling
- Comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`)
- Use approved verbs for function names

### Testing Approach
- **Always test in VM/test environment first** before production
- Test idempotency: Run setup scripts multiple times safely
- Test edge cases: Empty directories, special characters in filenames
- Test security: Attempt to bypass chroot, modify versions as user
- Test fail2ban: Verify IP banning and unbanning
- Test cross-platform: Linux and Windows clients

### Error Handling
- Scripts should fail gracefully with clear error messages
- Use colored output: Red for errors, Yellow for warnings, Green for success
- Log important operations for troubleshooting
- Validate prerequisites before making system changes
- Provide rollback instructions in documentation

### Backward Compatibility
- Maintain compatibility with:
  - Debian Linux (recent stable releases)
  - Windows Server 2008 R2+ (PowerShell 2.0+)
  - Bash 4.x+ (avoid Bash 5-specific features)
- Avoid breaking changes to:
  - Directory structure (`/home/<user>/uploads`, `/home/<user>/versions`)
  - Credential file formats
  - Configuration file formats

## Common Tasks

### Adding a New Server Feature
1. Update `setup.sh` with idempotent checks (grep existing config before adding)
2. Update `create_user.sh` if per-user setup needed
3. Test on clean Debian VM
4. Update README.md with new feature documentation
5. Add troubleshooting section if complex

### Adding a New Client Feature
1. Update both `upload.sh` (Linux) and `upload.ps1` (Windows) for parity
2. Update `setup-client.sh` and `setup-client.ps1` if automation needed
3. Test on multiple client OS versions
4. Update README.md with examples
5. Update manual scheduling section if applicable

### Adding a New Management Command
1. Add function to `manage_users.sh`
2. Update usage function with new command
3. Add to main case statement
4. Test with various users and edge cases
5. Document in README.md "User Management" section

### Fixing a Security Issue
1. Assess severity and impact
2. Create fix with minimal disruption
3. Test thoroughly in isolated environment
4. Update documentation with security note
5. Consider if users need to re-run setup scripts

## Known Limitations and Workarounds

### Chroot SFTP Restrictions
- **Issue**: All files in home directory must be root-owned
- **Workaround**: Only `uploads/` and `versions/` subdirectories are writable/readable by user
- **Note**: Cannot use `.bash*` files in user home (breaks chroot)

### inotify Event Timing
- **Issue**: Using `create` event captures incomplete files during upload
- **Solution**: Use only `close_write` and `moved_to` events (captures complete files)
- **Trade-off**: Very fast uploads may complete before close_write triggers

### fail2ban and Testing
- **Issue**: Testing authentication from same IP can trigger bans
- **Workaround**: Use `fail2ban-client unban --all` to clear bans
- **Production**: Consider whitelisting admin IPs in jail configuration

### Windows PowerShell 2.0 Compatibility
- **Issue**: Older cmdlets and syntax required for Windows Server 2008 R2
- **Solution**: Avoid PowerShell 3.0+ specific features
- **Testing**: Test on oldest supported Windows version

## Documentation Standards

### Code Documentation
- Every script must have header comment with:
  - Copyright (c) 2025 Yianni Bourkelis
  - MIT License reference
  - Brief description of purpose
  - Usage examples
- Functions must have comment describing purpose and parameters
- Complex logic blocks need explanatory comments

### README.md Structure
- Clear installation instructions (server and client)
- Usage examples with expected output
- Troubleshooting section for common issues
- Security configuration details
- Command reference tables

### Commit Messages
- Use present tense: "Add feature" not "Added feature"
- Reference issue numbers where applicable
- Be descriptive: Explain why, not just what
- Examples:
  - ✅ "Fix chroot issue by removing .bash* files from user home"
  - ❌ "Fix bug"

## Support and Community

### Getting Help
- Check README.md troubleshooting section first
- Review README.md for scope clarification
- Check GitHub Issues for similar problems
- Review fail2ban logs for connection issues

### Contributing
- All contributors must sign CLA (see CONTRIBUTING.md)
- Follow existing code style and patterns
- Add tests/verification steps in VM environment
- Update documentation with changes
- One feature per pull request

### License
- Project licensed under MIT License
- All contributions must be compatible with MIT
- Copyright notices must be maintained in all files

## Project Status and Roadmap

### Completed Features ✅
- Server setup with chroot SFTP and fail2ban
- Real-time snapshot monitoring with inotify
- Retention policies (GFS and age-based)
- User management (create, delete, list, info, history, restore, cleanup)
- Linux client with automated setup and git auto-updates
- Windows client with automated setup and scheduled tasks
- Hash-based upload optimization (skip unchanged files)
- Comprehensive documentation with troubleshooting

### Known Issues 🔧
- None currently tracked

### Future Enhancements (Not Committed) 💡
- Web interface for browsing/downloading versions
- Email notifications for backup failures
- Backup verification and integrity checks
- Remote backup replication to secondary servers
- Integration with cloud storage (S3, etc.)
- Support for other Linux distros (Ubuntu, CentOS)

## Critical Reminders

⚠️ **Always test in VM before production deployment**
⚠️ **Scripts modify system SSH configuration - review changes carefully**
⚠️ **Backup existing system configuration before running setup scripts**
⚠️ **fail2ban will ban IPs after failed login attempts - whitelist admin IPs**
⚠️ **Chroot SFTP requires strict directory ownership - follow documented structure**
⚠️ **Credentials are stored on disk - ensure proper file permissions**
⚠️ **Monitor disk usage - snapshots can grow large without retention cleanup**

---

*This file serves as a comprehensive guide for development, maintenance, and contributions to the termiNAS project. Keep it updated as the project evolves.*
