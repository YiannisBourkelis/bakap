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

### Server Requirements
- Debian Linux (tested on recent versions)
- Root or sudo access for setup
- OpenSSH server (installed automatically by setup script)

### Client Requirements
- Linux/Unix system (for Linux client) or Windows (for PowerShell client)
- Git (for cloning repository and updates)
- lftp or sshpass (installed automatically if needed)
- Basic knowledge of SFTP

## Installation

### Server Installation
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
   
   **Security Features Enabled:**
   - fail2ban protection against brute force attacks
   - SSH/SFTP authentication monitoring (5 failed attempts = 1 hour ban)
   - DOS protection (10 connection attempts in 60s = 10 minute ban)
   - IP blocking at firewall level (iptables)

5. Create backup users (run as root for each user):
   ```
   sudo ./src/server/create_user.sh <username>
   ```
   This creates a user with a secure random password, sets up directories, and applies restrictions.

### Client Installation

#### Installation Location Recommendations

The recommended installation location depends on your use case:

| Location | Rating | Best For | Notes |
|----------|--------|----------|-------|
| **`/opt/bakap`** | ⭐⭐⭐⭐⭐ | **Production systems** | Standard location for third-party software. Root-owned, system-wide, survives user account changes. **This is the default for `setup-client.sh`.** |
| `/usr/local/src/bakap` | ⭐⭐⭐⭐ | Alternative production | Also system-wide and root-owned. Traditionally used for locally built software. |
| `~/bakap` | ⭐⭐ | Testing only | User-specific, deleted with user account. Not suitable for root cron jobs or production use. |

**Recommendation:** Use `/opt/bakap` for all production client installations. This is where `setup-client.sh` clones the repository by default.

#### Manual Client Setup (Linux)

1. Clone the repository to the recommended location:
   ```bash
   sudo git clone https://github.com/YiannisBourkelis/bakap.git /opt/bakap
   ```

2. Make the client script executable:
   ```bash
   sudo chmod +x /opt/bakap/src/client/linux/upload.sh
   ```

3. Set up automated backups (see **Automated Linux Client Setup** below for the easy way).

#### Automated Linux Client Setup

The easiest way to configure Linux client backups is with the interactive setup script:

```bash
cd /opt/bakap
sudo ./src/client/linux/setup-client.sh
```

This script will:
- Clone the repository to `/opt/bakap` if not already present
- Prompt for backup configuration (local path, server, credentials, schedule)
- Optionally enable automatic updates from GitHub before each backup
- Create secure credential storage (mode 600)
- Set up cron job for scheduled backups
- Configure log rotation
- Offer to run a test backup immediately

**Example session:**
```
Enter the local path to backup: /var/www
Enter the backup server hostname or IP: backup.example.com
Enter the SFTP username: webserver1
Enter the SFTP password: ********
Confirm SFTP password: ********
Enter the destination path on server [/uploads]: /web-backups
Enter the backup time (HH:MM format, e.g., 02:00): 03:30
Enter a name for this backup job (alphanumeric, no spaces): web-backup

Would you like to enable automatic updates from GitHub? (y/n): y
```

The script creates:
- `/usr/local/bin/bakap-backup/web-backup.sh` (backup script)
- `/root/.bakap-credentials/web-backup.conf` (encrypted credentials, mode 600)
- Cron job running at 03:30 daily
- Log rotation for `/var/log/bakap-web-backup.log`

**Auto-Update Feature:**
If enabled, before each backup the script will:
1. Check for updates from GitHub (`git fetch`)
2. Automatically merge updates (`git merge --ff-only origin/main`)
3. Log update status in backup logs
4. Proceed with backup using the latest version

This ensures clients always use the latest security fixes and features.

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

#### Automated Linux Backup Setup (`src/client/linux/setup-client.sh`)

Interactive setup script that configures automated daily backups for Linux clients:

```bash
# Make it executable
chmod +x src/client/linux/setup-client.sh

# Run as root
sudo ./src/client/linux/setup-client.sh
```

**What it does:**
- Interactively prompts for backup configuration (path, server, credentials, schedule)
- Creates secure credentials file in `/root/.bakap-credentials/` (mode 600)
- Generates backup script in `/usr/local/bin/bakap-backup/`
- Configures log rotation for backup logs
- Adds cron job for automated daily backups
- Validates all settings and offers immediate test run

**Example Session:**
```
==========================================
Bakap Client Setup
==========================================
This script will help you configure automated daily backups.

ℹ Please provide the following information:

Local path to backup (e.g., /var/backup/web1): /var/backup/web1
Backup server hostname or IP: backup.example.com
Backup username: myuser
Backup password: ****
Confirm password: ****
Remote destination path (default: /uploads): /uploads
Backup time (HH:MM, e.g., 01:00): 01:00
Backup job name (default: web1): web1-production

==========================================
Configuration Summary
==========================================
Local path:      /var/backup/web1
Backup server:   backup.example.com
Username:        myuser
Remote path:     /uploads
Backup time:     01:00 daily
Job name:        web1-production

Is this correct? (y/n): y

==========================================
Installing Backup Configuration
==========================================
✓ Created scripts directory: /usr/local/bin/bakap-backup
✓ Created secure credentials file: /root/.bakap-credentials/web1-production.conf
✓ Created backup script: /usr/local/bin/bakap-backup/backup-web1-production.sh
✓ Created log rotation config: /etc/logrotate.d/bakap-web1-production
✓ Added cron job to run daily at 01:00
✓ lftp is installed

==========================================
Setup Complete!
==========================================

✓ Backup job 'web1-production' has been configured successfully!

ℹ Configuration details:
  • Backup script:    /usr/local/bin/bakap-backup/backup-web1-production.sh
  • Credentials:      /root/.bakap-credentials/web1-production.conf
  • Log file:         /var/log/bakap-web1-production.log
  • Schedule:         Daily at 01:00

ℹ Useful commands:
  • Test backup now:      /usr/local/bin/bakap-backup/backup-web1-production.sh
  • View logs:            tail -f /var/log/bakap-web1-production.log
  • List cron jobs:       crontab -l
  • Edit cron schedule:   crontab -e

Would you like to test the backup now? (y/n):
```

**What gets created:**
```
/usr/local/bin/bakap-backup/
  └── backup-web1-production.sh        # Backup script

/root/.bakap-credentials/
  └── web1-production.conf             # Secure credentials (mode 600)

/etc/logrotate.d/
  └── bakap-web1-production            # Log rotation config

/var/log/
  └── bakap-web1-production.log        # Backup logs

Cron job:
  0 1 * * * /usr/local/bin/bakap-backup/backup-web1-production.sh
```

**Multiple backup jobs:** Run the script multiple times to configure different backup jobs (e.g., web1, database, documents). Each gets its own script, credentials, logs, and schedule.

#### Automated Windows Backup Setup (`src/client/windows/setup-client.ps1`)

Interactive setup script that configures automated daily backups for Windows clients (Windows Server 2008 R2 and later):

```powershell
# Run PowerShell as Administrator, then:
cd path\to\bakap\src\client\windows
.\setup-client.ps1
```

**What it does:**
- Interactively prompts for backup configuration (path, server, credentials, schedule)
- Locates or prompts for path to `upload.ps1` script
- Creates secure credentials file in `C:\ProgramData\bakap-credentials\` (restricted to Administrators)
- Generates backup script in `C:\Program Files\bakap-backup\`
- Creates Windows Scheduled Task for daily automated backups
- Validates all settings and offers immediate test run

**Example Session:**
```
==========================================
Bakap Windows Client Setup
==========================================
This script will help you configure automated daily backups.

Please provide the following information:

Enter the local path to backup (e.g., C:\Data): C:\Data
Enter the backup server hostname or IP: backup.example.com
Enter the SFTP username: webserver1
Enter the SFTP password: ********
Confirm SFTP password: ********
Enter the destination path on server (default: /uploads): /uploads
Enter the backup time (HH:MM format, e.g., 02:00): 03:00
Enter a name for this backup job (alphanumeric, no spaces): web-backup
Found upload.ps1 at: C:\bakap\src\client\windows\upload.ps1
Use this location? (y/n): y
[OK] Using upload script: C:\bakap\src\client\windows\upload.ps1

==========================================
Configuration Summary
==========================================
Local path:      C:\Data
Backup server:   backup.example.com
Username:        webserver1
Remote path:     /uploads
Backup time:     03:00 daily
Job name:        web-backup

Is this correct? (y/n): y

==========================================
Installing Backup Configuration
==========================================
[OK] Created directory: C:\Program Files\bakap-backup
[OK] Created directory: C:\ProgramData\bakap-credentials
[OK] Created directory: C:\ProgramData\bakap-logs
[OK] Created secure credentials file: C:\ProgramData\bakap-credentials\web-backup.xml
[OK] Created backup script: C:\Program Files\bakap-backup\backup-web-backup.ps1
[OK] Created scheduled task: Bakap-Backup-web-backup
[OK] WinSCP found (recommended)

==========================================
Setup Complete!
==========================================

Backup job 'web-backup' has been configured successfully!

Configuration details:
  - Backup script:    C:\Program Files\bakap-backup\backup-web-backup.ps1
  - Credentials:      C:\ProgramData\bakap-credentials\web-backup.xml
  - Log file:         C:\ProgramData\bakap-logs\bakap-web-backup.log
  - Schedule:         Daily at 03:00

Useful commands:
  - Test backup now:      PowerShell.exe -ExecutionPolicy Bypass -File "C:\Program Files\bakap-backup\backup-web-backup.ps1"
  - View logs:            Get-Content "C:\ProgramData\bakap-logs\bakap-web-backup.log" -Tail 50
  - View scheduled task:  Get-ScheduledTask -TaskName 'Bakap-Backup-web-backup'
  - Run task manually:    Start-ScheduledTask -TaskName 'Bakap-Backup-web-backup'
  - Disable task:         Disable-ScheduledTask -TaskName 'Bakap-Backup-web-backup'

Would you like to test the backup now? (y/n):
```

**What gets created:**
```
C:\Program Files\bakap-backup\
  └── backup-web-backup.ps1            # Backup script

C:\ProgramData\bakap-credentials\
  └── web-backup.xml                   # Secure credentials (Administrators only)

C:\ProgramData\bakap-logs\
  └── bakap-web-backup.log             # Backup logs

Windows Scheduled Task:
  Name: Bakap-Backup-web-backup
  Runs as: NT AUTHORITY\SYSTEM
  Schedule: Daily at 03:00
```

**Requirements:**
- Windows Server 2008 R2 or later (PowerShell 2.0+)
- Administrator privileges
- `upload.ps1` script (in same directory or specify custom path)
- WinSCP (recommended) or PuTTY (pscp.exe) in PATH
  - Download WinSCP: https://winscp.net/
  - Download PuTTY: https://www.chiark.greenend.org.uk/~sgtatham/putty/

**Multiple backup jobs:** Run the script multiple times to configure different backup jobs. Each gets its own scheduled task, credentials, logs, and schedule.

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

#### Security Monitoring (fail2ban)

**Check fail2ban status:**
```bash
sudo systemctl status fail2ban
```

**View currently banned IPs:**
```bash
sudo fail2ban-client status sshd
sudo fail2ban-client status sshd-ddos
```

**View ban statistics and history:**
```bash
# Show all banned IPs across all jails
sudo fail2ban-client banned

# View detailed jail statistics
sudo fail2ban-client status

# Check fail2ban logs
sudo tail -f /var/log/fail2ban.log

# Count banned IPs today
sudo grep "$(date +%Y-%m-%d)" /var/log/fail2ban.log | grep "Ban" | wc -l
```

**Manually unban an IP (if needed):**
```bash
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>
sudo fail2ban-client set sshd-ddos unbanip <IP_ADDRESS>
```

**View recent failed SSH/SFTP authentication attempts:**
```bash
sudo grep "Failed password" /var/log/auth.log | tail -20
sudo grep "Connection closed by authenticating user" /var/log/auth.log | tail -20
```

**Security configuration details:**
- **Authentication failures**: 5 failed attempts within 10 minutes = 1 hour IP ban
- **DOS protection**: 10 connection attempts within 60 seconds = 10 minute IP ban
- **Scope**: Protects both SSH and SFTP (same authentication layer)
- **Action**: Complete IP block at firewall level (iptables)

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

#### Automated Setup (Recommended)

**Windows:** Use `src/client/windows/setup-client.ps1` (see [Automated Windows Backup Setup](#automated-windows-backup-setup-srcclientwindowssetup-clientps1) above)

**Linux:** Use `src/client/linux/setup-client.sh` (see [Automated Linux Backup Setup](#automated-linux-backup-setup-srcclientlinuxsetup-clientsh) above)

#### Manual Scheduling

If you prefer to manually configure scheduled backups:

**Windows - Task Scheduler (PowerShell):**
```powershell
# Method 1: Using PowerShell cmdlets (Windows Server 2012+, recommended)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password 'SecurePass123!' -Server backup.example.com -DestPath /uploads"

$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName "Bakap-Daily-Backup" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "NT AUTHORITY\SYSTEM" `
    -RunLevel Highest `
    -Description "Daily backup to bakap server"
```

**Windows - Task Scheduler (GUI method for older systems):**
1. Open **Task Scheduler** (`taskschd.msc`)
2. Click **Create Basic Task** in the right panel
3. Name: "Bakap Daily Backup", click **Next**
4. Trigger: Select **Daily**, click **Next**
5. Start time: Set your desired backup time (e.g., 2:00 AM), click **Next**
6. Action: Select **Start a program**, click **Next**
7. Program/script: `PowerShell.exe`
8. Add arguments:
   ```
   -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\bakap\src\client\windows\upload.ps1" -LocalPath "C:\Data" -Username "backupuser" -Password "SecurePass123!" -Server "backup.example.com" -DestPath "/uploads"
   ```
9. Click **Next**, then **Finish**
10. Right-click the task, select **Properties**
11. Under **General** tab:
    - Select "Run whether user is logged on or not"
    - Check "Run with highest privileges"
    - Change user to "SYSTEM" (click Change User, type "SYSTEM")
12. Under **Settings** tab:
    - Check "Run task as soon as possible after a scheduled start is missed"
    - Check "Start the task only if the computer is on AC power" (optional)
13. Click **OK**

**Windows - Legacy schtasks.exe (Windows Server 2008 R2):**
```cmd
schtasks /Create /SC DAILY /TN "Bakap-Daily-Backup" /TR "PowerShell.exe -ExecutionPolicy Bypass -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password SecurePass123! -Server backup.example.com -DestPath /uploads" /ST 02:00 /RU SYSTEM /RL HIGHEST
```

**Linux - Cron Job:**
```bash
# Edit root's crontab
sudo crontab -e

# Add this line to run backup daily at 2:00 AM
0 2 * * * /opt/bakap/src/client/linux/upload.sh -l /var/data -u backupuser -p "SecurePass123!" -s backup.example.com -d /uploads >> /var/log/bakap-backup.log 2>&1

# Optional: Add log rotation
# Create /etc/logrotate.d/bakap-backup with:
/var/log/bakap-backup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

**Cron Schedule Examples:**
```bash
# Every day at 2:00 AM
0 2 * * * /path/to/backup-script.sh

# Every day at 3:30 AM
30 3 * * * /path/to/backup-script.sh

# Every Sunday at 1:00 AM (weekly)
0 1 * * 0 /path/to/backup-script.sh

# Every 6 hours
0 */6 * * * /path/to/backup-script.sh

# Every 30 minutes
*/30 * * * * /path/to/backup-script.sh
```

**Security Notes:**
- For production use, avoid embedding passwords in command lines (visible in process lists)
- Use the automated setup scripts which store credentials securely
- On Windows: Credentials stored in `C:\ProgramData\bakap-credentials\` (restricted to Administrators)
- On Linux: Credentials stored in `/root/.bakap-credentials/` (mode 600)

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