# bakap Project

> **⚠️ EXPERIMENTAL SOFTWARE - USE WITH CAUTION**
>
> Bakap is currently in **experimental/alpha stage**. While it has been tested in development environments, it has not yet been extensively tested in production scenarios. Use at your own risk and **always maintain independent backups** of your critical data. The software may contain bugs, and breaking changes may occur in future releases.
>
> **Not recommended for production use without thorough testing in your specific environment.**

## Overview
Bakap is a secure, versioned backup server for Debian Linux using **Btrfs copy-on-write snapshots**. It allows remote clients to upload files via SFTP, storing them in user-specific folders with real-time incremental versioning for ransomware protection. Even if a client's local machine is infected, the server-side version history remains intact and unmodifiable. Clients can download previous versions of their files. Users are strictly chrooted to their home directories for security.

Key features:
- **Instant Btrfs snapshots** triggered by filesystem changes (millisecond creation time).
- **Ransomware protection** via immutable read-only Btrfs snapshots (cannot be modified even by root without explicit command).
- **Strict access control**: Users cannot access anything outside their home folder.
- **Superior storage efficiency**: Block-level copy-on-write (only changed blocks consume space).

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
- **Debian 13 (Trixie) or later** (requires Linux 6.x kernel for stable Btrfs support)
- **Btrfs filesystem for /home** (required for snapshot functionality)
- Root or sudo access for setup
- OpenSSH server (installed automatically by setup script)

### Setting Up Btrfs During Debian Installation
During Debian installation, when you reach the partitioning step:
1. Select **"Manual partitioning"**
2. Create a separate partition for `/home`
3. Format it as **Btrfs** filesystem
4. Or: Use Btrfs for the entire root filesystem (simpler, works fine)

**Example partitioning scheme:**
```
/dev/sda1  →  EFI System  →  512 MB
/dev/sda2  →  ext4        →  / (root)     →  30 GB
/dev/sda3  →  Btrfs       →  /home        →  remaining space
/dev/sda4  →  swap        →  8 GB
```

**Or convert existing system:**
```bash
# WARNING: This destroys all data on /home!
# Backup first: rsync -a /home/ /backup/home/

umount /home
mkfs.btrfs /dev/sdXY
mount /dev/sdXY /home

# Update /etc/fstab:
# UUID=xxx /home btrfs defaults,compress=zstd 0 2

# Restore data: rsync -a /backup/home/ /home/
```

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
   ```bash
   # Create user with auto-generated 64-character password
   sudo ./src/server/create_user.sh <username>
   
   # Or provide your own password (must be 30+ chars with lowercase, uppercase, and numbers)
   sudo ./src/server/create_user.sh <username> -p "YourSecurePassword123456789012345"
   ```
   This creates a user with a secure password, sets up Btrfs subvolumes, and applies restrictions.

### Client Installation

#### Installation Location Recommendations

The recommended installation location depends on your use case:

| Location | Best For | Notes |
|----------|----------|-------|
| **`/opt/bakap`** | **Production systems** | Standard location for third-party software. Root-owned, system-wide, survives user account changes. **This is the default for `setup-client.sh`.** |
| `/usr/local/src/bakap` | Alternative production | Also system-wide and root-owned. Traditionally used for locally built software. |
| `~/bakap` | Testing only | User-specific, deleted with user account. Not suitable for root cron jobs or production use. |

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
# First, clone the repository
git clone https://github.com/YiannisBourkelis/bakap.git
cd bakap

# Then run the setup script
sudo ./src/client/linux/setup-client.sh
```

This script will:
- Prompt for backup configuration (local path, server, credentials, schedule)
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
```

The script creates:
- `/usr/local/bin/bakap-backup/web-backup.sh` (backup script)
- `/root/.bakap-credentials/web-backup.conf` (credentials file, mode 600)
- Cron job running at 03:30 daily
- Log rotation for `/var/log/bakap-web-backup.log`

## Usage

### Client Upload Scripts

Bakap includes cross-platform client scripts for easy file uploads:

#### Windows Client (`src/client/windows/upload.ps1`)
PowerShell script with hash-based skipping and WinSCP support:
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
- Automatic WinSCP detection
- Process monitoring to prevent hanging
- Support for both files and directories
- Mirror mode: Deleted local files are also deleted from remote backup

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
[OK] WinSCP found

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
- WinSCP in PATH or specify path with `-WinSCPPath` parameter
  - Download WinSCP: https://winscp.net/

**Multiple backup jobs:** Run the script multiple times to configure different backup jobs. Each gets its own scheduled task, credentials, logs, and schedule.

### Server Administration

#### User Management (`src/server/manage_users.sh`)

Comprehensive tool for managing backup users and snapshots:

**List all users with disk usage:**
```bash
sudo ./src/server/manage_users.sh list
```
Shows username, actual disk usage, apparent size (before Btrfs deduplication), snapshot count, and last backup date/time.

**Get detailed user information:**
```bash
sudo ./src/server/manage_users.sh info <username>
```
Displays:
- User ID and group membership
- Disk usage breakdown (uploads, versions, space saved via Btrfs copy-on-write)
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
# Cleanup specific user (keeps only latest snapshot)
sudo ./src/server/manage_users.sh cleanup <username>

# Cleanup all users
sudo ./src/server/manage_users.sh cleanup-all
```
Removes old Btrfs snapshots while preserving the latest snapshot.

**Rebuild snapshots from current uploads:**
```bash
# Rebuild snapshots for a specific user
sudo ./src/server/manage_users.sh rebuild <username>

# Rebuild snapshots for all users
sudo ./src/server/manage_users.sh rebuild-all
```
Deletes ALL existing snapshots and creates a fresh Btrfs snapshot from the current uploads directory. This is useful when you need to:
- Clean up snapshot history and start fresh
- Fix corrupted or inconsistent snapshots
- Reduce disk space by eliminating snapshot history

**Features:**
- Automatically skips users with files currently open (warns and continues)
- Verifies file integrity after creating the new snapshot
- Compares file count and sizes between uploads and snapshot
- Provides detailed progress output and summary statistics

**Example output:**
```
==========================================
Rebuilding snapshots for user: testuser
==========================================
✓ No open files detected
Files to snapshot: 1247
Deleting 3 existing snapshot(s)...
  ✓ Deleted: 2025-10-08_14-30-00
  ✓ Deleted: 2025-10-09_08-15-22
  ✓ Deleted: 2025-10-09_12-45-10
Deleted 3 snapshot(s)
Creating fresh snapshot from uploads directory...
✓ Btrfs snapshot created: 2025-10-09_15-30-45
✓ Snapshot set to read-only
Verifying file integrity...
✓ File count matches: 1247 files
✓ All 1247 files verified successfully
✓ Snapshot rebuild completed successfully for user 'testuser'
```

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

**Update monitor service after git pull (applies new fixes/features):**
```bash
# Pull latest changes
cd /opt/bakap
git pull

# Re-run setup to update monitor script
sudo ./src/server/setup.sh

# Restart service to apply changes
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

#### Snapshot Timing Configuration

The monitor uses **smart periodic snapshots** that exclude in-progress files:

**How it works:**
1. **Immediate snapshot when all files complete**: No waiting - snapshot taken 30s after last file closes
2. **Periodic snapshots while uploading**: Takes snapshot every 30 minutes (default) if files are still open
3. **Excludes in-progress files**: Only completed (closed) files are included in periodic snapshots
4. **Efficient snapshot management**: Prevents excessive snapshot creation from frequent small file changes

**Example scenarios:**

**Scenario 1: Quick upload (all files complete quickly)**
```
03:00:00 - Start uploading: file1.sql (10 MB) + file2.sql (50 MB)
03:00:15 - Both files complete (all closed)
03:00:45 - Immediate snapshot: includes BOTH files (no 30-minute wait!)
```

**Scenario 2: Mixed upload (small + large files)**
```
03:00:00 - Start uploading: small.sql (10 MB) + huge.tar.gz (500 GB)
03:00:30 - small.sql completes (closed)
03:00:30 - huge.tar.gz still uploading (in progress...)
03:30:30 - Periodic snapshot #1: includes small.sql, EXCLUDES huge.tar.gz (still open)
04:00:30 - Periodic snapshot #2: includes small.sql, EXCLUDES huge.tar.gz (still open)
04:15:00 - huge.tar.gz completes (all files closed)
04:15:30 - Final snapshot: includes BOTH small.sql + huge.tar.gz (immediate!)
```

**Configuration** (edit `/etc/systemd/system/bakap-monitor.service`):

```bash
sudo nano /etc/systemd/system/bakap-monitor.service

# Add to [Service] section:
Environment="BAKAP_SNAPSHOT_INTERVAL=1800"  # Periodic interval while files open: 30 min (default)
Environment="BAKAP_COALESCE_WINDOW=30"      # Wait 30s after event before checking (default)
```

**Important:** `SNAPSHOT_INTERVAL` only applies **while files are still uploading**. When all files complete, snapshot is taken immediately (after the 30s coalesce window).

**Behavior Summary:**

| Scenario | Snapshot Timing | Notes |
|----------|----------------|-------|
| **All files complete quickly** | **30 seconds after last file** | No interval wait! Immediate snapshot. |
| **Files still uploading** | Every 30 minutes (default) | Periodic snapshots exclude in-progress files |
| **Large file finishes** | **30 seconds after close** | Immediate final snapshot with all files |

**Recommended intervals:**

| Upload Pattern | SNAPSHOT_INTERVAL | Notes |
|----------------|-------------------|-------|
| Many small files | 300 (5 min) | More frequent protection while uploading |
| Mixed sizes | 1800 (30 min) | **Default - balanced** |
| Few large files | 3600 (60 min) | Less overhead for long uploads |
| Continuous uploads | 7200 (2 hours) | Minimize snapshot count |

After changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart bakap-monitor.service
```

**Benefits:**
- ✅ **Immediate snapshot** when all files complete (30s delay only)
- ✅ Periodic snapshots protect small files while large files still upload
- ✅ Large files don't block small file protection
- ✅ Fewer snapshots than per-file approach (easier to manage)
- ✅ Perfect for mixed workloads (databases + large archives)

#### Optimizing for Very Large Files (100+ GB)

**1. Increase Btrfs commit interval** (reduce metadata overhead):
```bash
# Add to /etc/fstab mount options:
UUID=xxx /home btrfs defaults,compress=zstd,commit=120 0 2

# Remount:
sudo mount -o remount,commit=120 /home
```

**2. Disable atime updates** (faster file operations):
```bash
# Add to /etc/fstab:
UUID=xxx /home btrfs defaults,compress=zstd,noatime 0 2

sudo mount -o remount,noatime /home
```

**3. Increase disk cache** (better for large sequential writes):
```bash
# Add to /etc/sysctl.conf:
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 50

sudo sysctl -p
```

**4. Monitor disk I/O during uploads:**
```bash
# Real-time I/O stats
sudo iotop -o

# Check if disk is bottleneck
iostat -x 2
```

#### SSH Security

Additional hardening can be done in `/etc/ssh/sshd_config`:
- Restrict allowed authentication methods
- Configure connection limits
- Set up fail2ban for brute-force protection (configured automatically by setup.sh)

### Client Configuration

Both client scripts support configuration via command-line parameters. For automated backups, consider:

#### Automated Setup (Recommended)

**Windows:** Use `src/client/windows/setup-client.ps1` (see [Automated Windows Backup Setup](#automated-windows-backup-setup-srcclientwindowssetup-clientps1) above)

**Linux:** Use `src/client/linux/setup-client.sh` (see [Automated Linux Backup Setup](#automated-linux-backup-setup-srcclientlinuxsetup-clientsh) above)

#### Manual Scheduling

If you prefer to manually configure scheduled backups:

**Windows - Task Scheduler (PowerShell):**

Basic (WinSCP in PATH):
```powershell
# Method 1: Using PowerShell cmdlets (Windows Server 2012+, recommended)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password 'SecurePass123!' -Server backup.example.com -DestPath uploads"

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

With custom WinSCP path and host key verification:
```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password 'SecurePass123!' -Server backup.example.com -DestPath uploads -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com' -ExpectedHostFingerprint 'ssh-ed25519 255 AAAA...'"

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
8. Add arguments (basic - WinSCP in PATH):
   ```
   -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\bakap\src\client\windows\upload.ps1" -LocalPath "C:\Data" -Username "backupuser" -Password "SecurePass123!" -Server "backup.example.com" -DestPath "uploads"
   ```
   **Or with custom WinSCP path and host key verification:**
   ```
   -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\bakap\src\client\windows\upload.ps1" -LocalPath "C:\Data" -Username "backupuser" -Password "SecurePass123!" -Server "backup.example.com" -DestPath "uploads" -WinSCPPath "C:\Program Files\WinSCP\WinSCP.com" -ExpectedHostFingerprint "ssh-ed25519 255 AAAA..."
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

Basic (WinSCP in PATH):
```cmd
schtasks /Create /SC DAILY /TN "Bakap-Daily-Backup" /TR "PowerShell.exe -ExecutionPolicy Bypass -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password SecurePass123! -Server backup.example.com -DestPath uploads" /ST 02:00 /RU SYSTEM /RL HIGHEST
```

With custom WinSCP path and host key verification:
```cmd
schtasks /Create /SC DAILY /TN "Bakap-Daily-Backup" /TR "PowerShell.exe -ExecutionPolicy Bypass -File C:\bakap\src\client\windows\upload.ps1 -LocalPath C:\Data -Username backupuser -Password SecurePass123! -Server backup.example.com -DestPath uploads -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com' -ExpectedHostFingerprint 'ssh-ed25519 255 AAAA...'" /ST 02:00 /RU SYSTEM /RL HIGHEST
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

**Host Key Verification (TOFU - Trust On First Use):**
- First connection: Script accepts any host key and caches fingerprint in `%LOCALAPPDATA%\bakap\hostkeys\`
- Subsequent connections: Script verifies server fingerprint against cached value
- Cache location depends on user running the task:
  - `NT AUTHORITY\SYSTEM` (recommended): `C:\Windows\System32\config\systemprofile\AppData\Local\bakap\`
  - Admin user: `C:\Users\<username>\AppData\Local\bakap\`
- If server key changes (e.g., server reinstall), task will fail with exit code 6
- To reset trust: Delete the cached fingerprint file and let the script recapture it
- For paranoid security: Manually provide `-ExpectedHostFingerprint` parameter to bypass TOFU

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

## Troubleshooting

### Windows Client Issues

**Problem: Scheduled task fails with exit code 6 (fingerprint extraction failed)**

Possible causes:
1. First run failed to extract host fingerprint from WinSCP log
2. WinSCP log format changed (report this as a bug)

Solutions:
```powershell
# Option 1: Enable debug mode and check logs
Get-Content "C:\ProgramData\bakap-logs\bakap-<jobname>.log" -Tail 100

# Option 2: Manually provide the expected fingerprint
# Get fingerprint from server:
ssh-keyscan -t ed25519 backup.example.com

# Add to credentials file or use -ExpectedHostFingerprint parameter to upload.ps1
```

**Problem: Scheduled task fails after server reinstall/key change**

This is expected behavior! The cached fingerprint no longer matches.

Solution:
```powershell
# Delete cached fingerprint to re-establish trust
Remove-Item "C:\Windows\System32\config\systemprofile\AppData\Local\bakap\hostkeys\backup.example.com.txt"

# Next scheduled run will accept new key and cache it
```

**Problem: WinSCP hangs after successful upload**

This is a known WinSCP issue with the console version. The script includes hang detection.

Mitigation:
- Script monitors for "No session." message + 5-second silence
- Automatically force-kills hung WinSCP processes
- Upload completes successfully despite hang

**Problem: Task Scheduler shows "Task has not yet run"**

Verify:
```powershell
# Check task configuration
Get-ScheduledTask -TaskName "Bakap-Backup-<jobname>" | Format-List *

# Check task trigger
Get-ScheduledTask -TaskName "Bakap-Backup-<jobname>" | Select-Object -ExpandProperty Triggers

# Manually trigger task to test
Start-ScheduledTask -TaskName "Bakap-Backup-<jobname>"

# Check execution history
Get-ScheduledTask -TaskName "Bakap-Backup-<jobname>" | Get-ScheduledTaskInfo
```

### Linux Client Issues

**Problem: "lftp: command not found" or "sftp: command not found"**

Solution:
```bash
# Install lftp (recommended)
sudo apt-get install lftp

# Or install openssh-client for sftp
sudo apt-get install openssh-client
```

**Problem: "Host key verification failed"**

Solution:
```bash
# Accept host key manually first
ssh-keyscan -H backup.example.com >> ~/.ssh/known_hosts

# Or use --accept-hostkey option in upload script
./upload.sh -l /data -u user -p pass -s server --accept-hostkey
```

### Server Issues

**Problem: fail2ban bans legitimate clients**

Check ban status:
```bash
sudo fail2ban-client status sshd
```

Unban IP:
```bash
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>
```

Whitelist trusted IPs (edit `/etc/fail2ban/jail.local`):
```ini
[sshd]
ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24 10.0.0.0/8
```

**Problem: Snapshots missing files or contain incomplete files**

**This is now fixed!** The new monitor logic creates **periodic snapshots** (every 30 minutes) that automatically exclude in-progress files.

**How it works:**
- Small completed files are included in snapshots within 30 minutes
- Large files still uploading are excluded from periodic snapshots
- Final snapshot is created when ALL files complete

Update your installation:
```bash
# Pull latest fix
cd /opt/bakap
git pull

# Re-run setup to update monitor script
sudo ./src/server/setup.sh

# Restart service
sudo systemctl restart bakap-monitor.service

# Verify new logic is applied
sudo grep "Excluding in-progress" /var/backups/scripts/monitor_backups.sh
```

**Monitor the snapshot process:**

```bash
# Watch for open files in uploads directory
sudo watch -n 1 "lsof +D /home/*/uploads 2>/dev/null | grep -E '\s+[0-9]+[uw]'"

# Check monitor logs to see exclusions
sudo tail -f /var/log/backup_monitor.log

# Example log output (10 MB + 500 GB mixed upload):
# 2025-10-09 03:00:30 Activity for eventsaxd: waiting for interval or completion
# 2025-10-09 03:30:30 Excluding in-progress files from snapshot:
# 2025-10-09 03:30:30   Excluded: huge.tar.gz (387GB, still uploading)
# 2025-10-09 03:30:31 Btrfs snapshot created for eventsaxd (periodic (1800s since last, 1 files still open), excluded 1 in-progress files)
# 2025-10-09 04:00:30 Excluding in-progress files from snapshot:
# 2025-10-09 04:00:30   Excluded: huge.tar.gz (465GB, still uploading)
# 2025-10-09 04:00:31 Btrfs snapshot created for eventsaxd (periodic (1800s since last, 1 files still open), excluded 1 in-progress files)
# 2025-10-09 04:15:00 huge.tar.gz upload completes
# 2025-10-09 04:15:30 Btrfs snapshot created for eventsaxd (all files closed)

# Example log output (quick upload - all files complete fast):
# 2025-10-09 05:00:10 files.tar.gz upload completes
# 2025-10-09 05:00:40 Btrfs snapshot created for eventsaxd (all files closed)
# ↑ Immediate snapshot (no 30-minute wait!)
```

**Verify excluded files:**
```bash
# Check periodic snapshot (in-progress file excluded)
ls -lh /home/user/versions/2025-10-09_03-30-31/
# Shows: small.sql (10 MB), huge.tar.gz MISSING

# Check final snapshot (all files present)
ls -lh /home/user/versions/2025-10-09_04-15-25/
# Shows: small.sql (10 MB), huge.tar.gz (500 GB)
```

**View snapshot history:**
```bash
# List all snapshots for a user
ls -lht /home/eventsaxd/versions/

# Compare snapshots (see what changed)
diff -r /home/eventsaxd/versions/2025-10-09_03-00-08 \
        /home/eventsaxd/versions/2025-10-09_04-30-15
```

**For very large files (500+ GB):**

The monitor automatically handles files of any size by waiting until they're fully closed. However, if uploads take longer than 10 minutes (default `BAKAP_MAX_WAIT=600`), increase the timeout:

```bash
sudo nano /etc/systemd/system/bakap-monitor.service

# Add to [Service] section:
Environment="BAKAP_MAX_WAIT=1800"  # 30 minutes for very slow uploads

sudo systemctl daemon-reload
sudo systemctl restart bakap-monitor.service
```

**Best practices:**
1. Upload during off-peak hours (less I/O contention)
2. Monitor logs to verify snapshots capture complete files
3. Use fast network (10 Gbps) for massive file uploads
4. Consider dedicated backup disk/network for better throughput

**Problem: Snapshots not being created**

Check monitor service:
```bash
sudo systemctl status bakap-monitor.service
sudo journalctl -u bakap-monitor.service -f
```

Check inotify limits:
```bash
# Current limits
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances

# Increase if needed (edit /etc/sysctl.conf)
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512

# Apply
sudo sysctl -p
```

**Problem: Disk full due to too many snapshots**

Manually trigger cleanup:
```bash
sudo /var/backups/scripts/cleanup_snapshots.sh
```

Adjust retention policy in `/etc/bakap-retention.conf`:
```bash
# Reduce retention for all users
KEEP_DAILY=3
KEEP_WEEKLY=2
KEEP_MONTHLY=1

# Or disable advanced retention
ENABLE_ADVANCED_RETENTION=false
RETENTION_DAYS=7
```
