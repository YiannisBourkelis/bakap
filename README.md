# bakap Project

## Overview
Bakap is a secure, versioned backup server for Debian Linux. It allows remote clients to upload files or directories using SCP or SFTP, storing them in user-specific folders with real-time incremental versioning for ransomware protection. Even if a client's local machine is infected, the server-side version history remains intact and unmodifiable. Clients can download previous versions of their files. Users are strictly chrooted to their home directories for security.

Key features:
- Real-time incremental snapshots triggered by filesystem changes.
- Ransomware protection via immutable, root-owned version history.
- Strict access control: Users cannot access anything outside their home folder.
- Efficient storage using hardlinks for unchanged files.

## Prerequisites
- Debian Linux (tested on recent versions).
- Root or sudo access for setup.
- OpenSSH server (installed automatically by setup script).
- Basic knowledge of SFTP for client uploads/downloads.

## Installation
1. Clone the repository:
   ```
   git clone https://github.com/YiannisBourkelis/bakap.git
   ```
2. Navigate to the project directory:
   ```
   cd bakap
   ```
3. Make the scripts executable:
   ```
   chmod +x setup.sh create_user.sh delete_user.sh
   ```
4. Run the setup script as root:
   ```
   sudo ./setup.sh
   ```
   This installs required packages, configures SSH/SFTP with restrictions, sets up real-time monitoring, and prepares the server.

5. Create backup users (run as root for each user):
   ```
   sudo ./create_user.sh <username>
   ```
   This creates a user with a secure random password, sets up directories, and applies restrictions.

6. Delete backup users (run as root, with confirmation):
   ```
   sudo ./delete_user.sh <username>
   ```
   This removes the user and all their data (uploads and versions).

## Usage
- **For Administrators**:
  - Use `create_user.sh` to add users. Note the generated password for distribution.
  - Monitor logs at `/var/log/backup_monitor.log` for snapshot activity.

- **For Users**:
  - Upload files: Use SFTP to connect and upload to your home directory (e.g., `sftp username@server`, then `put file.txt`).
  - Downloads: Access `/versions` via SFTP to browse and download snapshots (e.g., `get /versions/20250929130000/* /local/path`).
  - Snapshots are created automatically on any file changes (add, modify, delete, move).

## Development
To modify or extend the scripts:
- Edit `setup.sh` for server configuration changes.
- Edit `create_user.sh` for user setup tweaks.
- Test in a VM to avoid disrupting production.

## Contributing
Contributions are welcome! Before contributing, please review our [Contributing Guide](CONTRIBUTING.md), which includes our Contributor License Agreement (CLA). All contributors must agree to the CLA to have their changes accepted.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.