# Changelog

All notable changes to termiNAS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-alpha.1] - 2025-10-19

### Added
- Initial alpha release of termiNAS backup server
- **Core Features**:
  - Real-time incremental snapshot system using Btrfs and inotify
  - Ransomware protection via root-owned, immutable snapshot versions
  - Chroot SFTP-only access for backup users
  - fail2ban integration for SSH/SFTP brute force protection
  - Flexible retention policies (Grandfather-Father-Son or age-based)
  - Per-user configurable retention settings

- **Server Scripts**:
  - `setup.sh`: Automated server installation and configuration with optional Samba support
  - `create_user.sh`: Create backup users with secure 64-character passwords
  - `delete_user.sh`: Delete users with safety confirmation prompt
  - `manage_users.sh`: Comprehensive management tool with 17 commands:
    - User listing with disk usage, snapshot counts, and connection status
    - Detailed user info with connection activity tracking
    - Snapshot history and search capabilities
    - Inactive user detection
    - File restoration from snapshots
    - Snapshot cleanup and rebuild operations
    - Samba/SMB share management (enable/disable per user)
    - Time Machine support for macOS clients
    - Read-only SMB access to version snapshots

- **Client Support**:
  - **Linux Client**:
    - `setup-client.sh`: Interactive automated backup setup with cron scheduling
    - `upload.sh`: Manual upload with SHA-256 hash checking to skip unchanged files
    - Support for lftp (preferred) and sftp
  - **Windows Client**:
    - `setup-client.ps1`: Interactive automated backup setup with Task Scheduler
    - `upload.ps1`: Manual upload with SHA-256 hash checking and incremental sync
    - WinSCP integration for SFTP transfers
    - PowerShell 2.0+ compatibility (Windows Server 2008 R2+)

- **Security Features**:
  - Chroot environment prevents filesystem traversal
  - Root-owned snapshots prevent client modification/deletion
  - fail2ban DOS and brute force protection
  - SSH key or strong password authentication (64 characters default)
  - Secure credential storage on clients (restrictive permissions)
  - Optional Samba sharing with strict security settings

- **Storage Efficiency**:
  - Btrfs Copy-on-Write (CoW) snapshots with automatic block-level deduplication for minimal disk space usage
  - Retention policies to manage snapshot growth

- **Documentation**:
  - Comprehensive README with installation, usage, and troubleshooting
  - PROJECT_REQUIREMENTS.md detailing original scope and goals
  - CONTRIBUTING.md with Contributor License Agreement
  - Inline script comments and usage help in all tools

- **Version Tracking**:
  - VERSION file in repository root (1.0.0-alpha.1)
  - All scripts read version from central VERSION file
  - `--version` flags in setup.sh and manage_users.sh
  - Version information in PowerShell script help headers

### Requirements
- Debian 12+ (Btrfs filesystem required for /home)
- OpenSSH with chroot SFTP support (strict directory ownership enforced)
- inotify-tools for real-time filesystem monitoring
- Windows clients require WinSCP for SFTP transfers
- Linux clients work best with lftp (falls back to sftp)

### Changed
- Enhanced manage_users.sh output formatting:
  - Widened columns for better readability (Size, Apparent, Protocol, Last Snapshot, Last SFTP, Last SMB)
  - Right-aligned numeric and date columns
  - Status column with proper alignment
  - Improved separator lines for clean table display

### Fixed
- Safety confirmation in delete_user.sh now requires typing exact username (prevents accidental deletions)
- Snapshot timing uses `close_write` and `moved_to` events to avoid capturing incomplete files
- Proper handling of special characters in filenames
- Correct chroot directory ownership (root:root for parent, user permissions for subdirectories)

### Security
- All backup users created with nologin shell (SFTP-only access)
- fail2ban configured for both brute force and DOS protection
- Credentials stored with 600 permissions (Linux) or Administrators-only (Windows)
- Optional Samba shares use strict security settings (no guest access by default)

### Known Limitations
- Guest/anonymous access without password not supported (all access requires authentication)
- Single server deployment only (no built-in replication to secondary servers)
- No web interface for browsing or downloading backup versions
- No email notifications for backup failures or warnings

---

## [Unreleased]

---

[1.0.0-alpha.1]: https://github.com/YiannisBourkelis/terminas/releases/tag/v1.0.0-alpha.1
