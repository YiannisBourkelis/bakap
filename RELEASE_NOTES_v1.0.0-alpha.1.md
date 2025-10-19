# termiNAS v1.0.0-alpha.1 - First Alpha Release 🎉

**Release Date:** October 19, 2025

This is the first alpha release of **termiNAS**, a secure, versioned backup server for Debian Linux that provides ransomware protection through real-time incremental snapshots.

---

## 🌟 Highlights

- **Ransomware Protection**: Server-side immutable snapshots that clients cannot modify or delete
- **Real-time Versioning**: Automatic Btrfs snapshots triggered by filesystem changes
- **Cross-Platform Clients**: Automated setup for both Linux and Windows
- **Secure Access**: Chroot SFTP-only with fail2ban protection
- **Space Efficient**: Btrfs Copy-on-Write with automatic block-level deduplication
- **Easy Management**: Comprehensive CLI tool with 17 commands

---

## 📦 What's Included

### Server Components
- **`setup.sh`**: One-command server installation with optional Samba support
- **`create_user.sh`**: Create backup users with secure 64-character passwords
- **`delete_user.sh`**: Delete users with safety confirmation (requires typing username)
- **`manage_users.sh`**: Full-featured management tool:
  - List users with disk usage and connection status
  - View snapshot history and search files
  - Restore files from any snapshot
  - Cleanup and rebuild operations
  - Samba/SMB share management
  - macOS Time Machine support

### Client Support
**Linux:**
- Interactive setup wizard (`setup-client.sh`)
- Manual upload script (`upload.sh`) with SHA-256 hash checking
- Automatic cron scheduling
- Support for lftp (preferred) or sftp

**Windows:**
- Interactive setup wizard (`setup-client.ps1`)
- Manual upload script (`upload.ps1`) with SHA-256 hash checking
- Task Scheduler integration
- WinSCP-based SFTP transfers
- PowerShell 2.0+ compatibility (Windows Server 2008 R2+)

### Security Features
- Chroot SFTP environment prevents filesystem traversal
- Root-owned snapshots immune to client-side malware
- fail2ban protection against brute force and DOS attacks
- Strong password defaults (64 characters)
- Secure credential storage

### Storage Features
- Btrfs Copy-on-Write snapshots
- Automatic block-level deduplication
- Flexible retention policies:
  - Grandfather-Father-Son (default)
  - Simple age-based
  - Per-user overrides
- Disk usage reporting (actual vs. apparent)

---

## 🚀 Quick Start

### Server Installation (Debian 12+)
```bash
git clone https://github.com/YiannisBourkelis/terminas.git
cd terminas/src/server
sudo ./setup.sh
sudo ./create_user.sh mybackupuser
```

### Linux Client Setup
```bash
cd terminas/src/client/linux
sudo ./setup-client.sh
```

### Windows Client Setup
```powershell
# Run as Administrator
cd terminas\src\client\windows
.\setup-client.ps1
```

---

## 📋 System Requirements

**Server:**
- Debian 12+ with Btrfs filesystem on /home
- OpenSSH server with chroot SFTP support
- inotify-tools for real-time monitoring

**Clients:**
- Linux: Bash 4.x+, lftp (recommended) or sftp
- Windows: PowerShell 2.0+, WinSCP

---

## 📚 Documentation

- **[README.md](README.md)**: Complete installation and usage guide
- **[CHANGELOG.md](CHANGELOG.md)**: Detailed change history
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Contribution guidelines with CLA
- **[PROJECT_REQUIREMENTS.md](PROJECT_REQUIREMENTS.md)**: Original project scope

---

## ⚠️ Alpha Release Notice

This is an **alpha release** intended for:
- Early adopters and testers
- Evaluation in non-production environments
- Feedback and bug reports

**Please:**
- Test thoroughly before production use
- Report issues on [GitHub Issues](https://github.com/YiannisBourkelis/terminas/issues)
- Review security settings for your environment
- Backup your backup server configuration

---

## 🔒 Known Limitations

- Guest/anonymous access not supported (authentication required)
- Single server deployment only (no built-in replication)
- No web interface for browsing versions
- No email notifications for backup failures
- Designed specifically for Debian 12+ (Btrfs requirement)

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

All contributors must sign the Contributor License Agreement (CLA).

---

## 📄 License

termiNAS is licensed under the [MIT License](LICENSE).

Copyright (c) 2025 Yianni Bourkelis

---

## 🙏 Support

- **Issues**: [GitHub Issues](https://github.com/YiannisBourkelis/terminas/issues)
- **Discussions**: [GitHub Discussions](https://github.com/YiannisBourkelis/terminas/discussions)
- **Email**: [Your contact email if you want to include it]

---

## 🗺️ Roadmap (Future Versions)

Planned features for future releases:
- Backup verification and integrity checks
- Remote replication to secondary servers
- Cloud storage integration (S3, etc.)
- Support for additional Linux distributions

---

**Download:** Use the source code archives below or clone the repository at the v1.0.0-alpha.1 tag.

**Upgrade Path:** This is the first release, so no upgrade is needed.

**Next Steps:**
1. Install on a test Debian server
2. Configure your first backup user
3. Set up a client (Linux or Windows)
4. Test backup and restore operations
5. Provide feedback!

Thank you for trying termiNAS! 🚀
