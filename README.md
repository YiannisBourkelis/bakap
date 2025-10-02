# bakap Project

## Overview
Bakap is a secure, versioned backup server for Debian Linux. It allows remote clients to upload files or directories using SCP or SFTP, storing them in user-specific folders with real-time incremental versioning for ransomware protection. Even if a client's local machine is infected, the server-side version history remains intact and unmodifiable. Clients can download previous versions of their files. Users are strictly chrooted to their home directories for security.

Key features:
- Real-time incremental snapshots triggered by filesystem changes.
- Ransomware protection via immutable, root-owned version history.
- Strict access control: Users cannot access anything outside their home folder.
- Efficient storage using hardlinks for unchanged files.

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK**

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages or other liability, whether in an action of contract, tort or otherwise, arising from, out of or in connection with the software or the use or other dealings in the software.

**Important Notes:**
- This software modifies system configurations including SSH/SFTP settings, user accounts, and file permissions.
- Always test in a non-production environment (VM or test server) before deploying to production.
- Ensure you have proper backups of your system before running setup scripts.
- Review all scripts and understand what they do before executing them with root privileges.
- The authors are not responsible for any data loss, system damage, or security breaches.
- Security configurations should be reviewed and hardened based on your specific requirements.

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
   chmod +x src/server/setup.sh src/server/create_user.sh src/server/delete_user.sh src/server/manage_users.sh
   ```
4. Run the setup script as root:
   ```
   sudo ./src/server/setup.sh
   ```
   This installs required packages, configures SSH/SFTP with restrictions, sets up real-time monitoring with configurable retention policies, and prepares the server.

5. Create backup users (run as root for each user):
   ```
   sudo ./src/server/create_user.sh <username>
   ```
   This creates a user with a secure random password, sets up directories, and applies restrictions.

## Usage

### Client Upload Scripts

Bakap includes cross-platform client scripts for easy file uploads:

#### Windows Client (`src/client/windows/upload.ps1`)
PowerShell script with hash-based skipping and WinSCP/pscp support:
```powershell
# Upload a file
.\upload.ps1 -LocalPath "C:\data\file.txt" -User backupuser -Password "pass" -Server backup.example.com

# Upload a directory
.\upload.ps1 -LocalPath "C:\data\folder" -User backupuser -Password "pass" -Server backup.example.com -DestinationPath "/data"

# Force upload (skip hash check)
.\upload.ps1 -LocalPath "C:\data\file.txt" -User backupuser -Password "pass" -Server backup.example.com -Force
```

**Parameters:**
- `-LocalPath` (required): File or directory to upload
- `-User` (required): SFTP username
- `-Password` (required): SFTP password
- `-Server` (required): Server hostname or IP
- `-DestinationPath` (optional): Remote path (defaults to `/uploads`)
- `-Port` (optional): SFTP port (default: 22)
- `-Force` (optional): Skip hash check, always upload

**Features:**
- SHA-256 hash checking to skip unchanged files
- Automatic WinSCP/pscp detection
- Process monitoring to prevent hanging
- Support for both files and directories

#### Linux Client (`src/client/linux/upload.sh`)
Bash script with lftp/sftp support and named parameters:
```bash
# Upload a file
./upload.sh -l /data/file.txt -u backupuser -p "pass" -s backup.example.com

# Upload a directory
./upload.sh -l /data/folder -u backupuser -p "pass" -s backup.example.com -d /backups

# Force upload and enable debug mode
./upload.sh -l /data/file.txt -u backupuser -p "pass" -s backup.example.com --force --debug
```

**Parameters:**
- `-l, --local-path` (required): File or directory to upload
- `-u, --user` (required): SFTP username
- `-p, --password` (required): SFTP password
- `-s, --server` (required): Server hostname or IP
- `-d, --dest-path` (optional): Remote path (default: `/uploads`)
- `-f, --force` (optional): Skip hash check, always upload
- `--port` (optional): SFTP port (default: 22)
- `--debug` (optional): Enable debug output

**Features:**
- SHA-256 hash checking to skip unchanged files
- Automatic lftp/sftp detection
- Mirror mode for directory uploads (uploads contents)
- Host key auto-acceptance option

### Server Administration

#### User Management (`src/server/manage_users.sh`)

Comprehensive tool for managing backup users and snapshots:

**List all users with disk usage:**
```bash
sudo ./src/server/manage_users.sh list
```
Shows username, actual disk usage, apparent size (before hardlink deduplication), and snapshot count.

**Get detailed user information:**
```bash
sudo ./src/server/manage_users.sh info <username>
```
Displays:
- User ID and group membership
- Disk usage breakdown (uploads, versions, space saved via hardlinks)
- Snapshot statistics (oldest, newest, total count)
- Upload activity and last upload time
- Custom retention policy (if configured)

**View snapshot history:**
```bash
sudo ./src/server/manage_users.sh history <username>
```
Lists all snapshots with size and file count for a specific user.

**Search for files across all users:**
```bash
sudo ./src/server/manage_users.sh search "*.pdf"
sudo ./src/server/manage_users.sh search "invoice_*"
```
Searches through the latest snapshot of each user.

**Find inactive users:**
```bash
sudo ./src/server/manage_users.sh inactive        # Default: 30 days
sudo ./src/server/manage_users.sh inactive 60     # Custom: 60 days
```
Lists users with no uploads in the specified time period.

**Restore files from a snapshot:**
```bash
sudo ./src/server/manage_users.sh restore <username> <snapshot> <destination>
# Example:
sudo ./src/server/manage_users.sh restore produser 2025-10-01_14-30-00 /tmp/restore
```
Copies files from a specific snapshot to a local destination (with progress display).

**Cleanup old snapshots:**
```bash
# Cleanup specific user (keeps only latest snapshot with actual files)
sudo ./src/server/manage_users.sh cleanup <username>

# Cleanup all users
sudo ./src/server/manage_users.sh cleanup-all
```
Removes hardlinked snapshots while preserving the latest snapshot with actual file data.

**Delete a user:**
```bash
sudo ./src/server/manage_users.sh delete <username>
```
Removes the user account and all their data (requires confirmation).

#### Retention Policy Configuration

Edit `/etc/bakap-retention.conf` to customize snapshot retention:

**Advanced Retention (Default - Grandfather-Father-Son):**
```bash
ENABLE_ADVANCED_RETENTION=true
KEEP_DAILY=7        # Keep last 7 daily snapshots
KEEP_WEEKLY=4       # Keep last 4 weekly snapshots (one per week)
KEEP_MONTHLY=6      # Keep last 6 monthly snapshots (one per month)
```

**Simple Age-Based Retention:**
```bash
ENABLE_ADVANCED_RETENTION=false
RETENTION_DAYS=30   # Delete snapshots older than 30 days
```

**Per-User Overrides:**
```bash
# Production user: extended retention
produser_KEEP_DAILY=30
produser_KEEP_WEEKLY=12
produser_KEEP_MONTHLY=24

# Test user: minimal retention
testuser_ENABLE_ADVANCED_RETENTION=false
testuser_RETENTION_DAYS=7
```

The cleanup script runs daily at 3:00 AM (configurable via `CLEANUP_HOUR` in the config file).

**Manual cleanup:**
```bash
sudo /var/backups/scripts/cleanup_snapshots.sh
```

#### Monitoring

**View backup activity logs:**
```bash
sudo tail -f /var/log/backup_monitor.log
```

**Check monitor service status:**
```bash
sudo systemctl status bakap-monitor.service
```

**Restart monitor service:**
```bash
sudo systemctl restart bakap-monitor.service
```

### For End Users (SFTP Access)

- **Upload files**: Use SFTP to connect and upload to the `uploads` directory:
  ```bash
  sftp username@server
  cd uploads
  put file.txt
  put -r directory/
  ```

- **Download snapshots**: Access the `versions` directory to browse and download snapshots:
  ```bash
  sftp username@server
  cd versions
  ls                                    # List all snapshots
  cd 2025-10-01_14-30-00                # Enter specific snapshot
  get -r . /local/restore/path          # Download entire snapshot
  ```

- **Snapshots**: Created automatically on any file changes (add, modify, delete, move). Each snapshot is timestamped in `YYYY-MM-DD_HH-MM-SS` format.

## Configuration Options

### Server Configuration

- **Debounce Settings**: Control snapshot frequency by setting environment variables:
  ```bash
  # In /etc/systemd/system/bakap-monitor.service, add to [Service] section:
  Environment="BAKAP_DEBOUNCE_SECONDS=10"     # Coalesce events within 10 seconds
  Environment="BAKAP_SNAPSHOT_DELAY=5"        # Wait 5 seconds before snapshotting
  ```

- **SSH Security**: Additional hardening can be done in `/etc/ssh/sshd_config`:
  - Restrict allowed authentication methods
  - Configure connection limits
  - Set up fail2ban for brute-force protection (recommended, install separately)

### Client Configuration

Both client scripts support configuration via command-line parameters. For automated backups, consider:

**Windows (Scheduled Task):**
```powershell
# Create a scheduled task to run daily
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\backup\upload.ps1 -LocalPath C:\data -User backupuser -Password pass -Server backup.example.com"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DailyBackup" -Description "Daily backup to bakap server"
```

**Linux (Cron Job):**
```bash
# Add to crontab (crontab -e)
0 2 * * * /path/to/upload.sh -l /data -u backupuser -p "pass" -s backup.example.com >> /var/log/backup.log 2>&1
```

## Development
To modify or extend the scripts:
- Edit `src/server/setup.sh` for server configuration changes
- Edit `src/server/create_user.sh` for user setup tweaks
- Edit `src/server/manage_users.sh` to add new management commands
- Edit client scripts (`src/client/windows/upload.ps1` or `src/client/linux/upload.sh`) for upload behavior
- Test in a VM to avoid disrupting production

**Key Files:**
- `src/server/setup.sh` - Server initialization and configuration
- `src/server/create_user.sh` - User creation with password generation
- `src/server/delete_user.sh` - User deletion
- `src/server/manage_users.sh` - User and snapshot management
- `src/client/windows/upload.ps1` - Windows PowerShell upload client
- `src/client/linux/upload.sh` - Linux Bash upload client
- `/var/backups/scripts/monitor_backups.sh` - Real-time snapshot monitor (created by setup)
- `/var/backups/scripts/cleanup_snapshots.sh` - Retention policy cleanup (created by setup)
- `/etc/bakap-retention.conf` - Retention configuration (created by setup)

## Contributing
Contributions are welcome! Before contributing, please review our [Contributing Guide](CONTRIBUTING.md), which includes our Contributor License Agreement (CLA). All contributors must agree to the CLA to have their changes accepted.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.