<#
.SYNOPSIS
  Interactive setup for automated Windows backup to bakap server.

.DESCRIPTION
  Bakap Windows Client Setup
  Copyright (c) 2025 Yianni Bourkelis
  Licensed under the MIT License - see LICENSE file for details
  https://github.com/YiannisBourkelis/bakap
  
  Compatible with Windows Server 2008 R2 and later (PowerShell 2.0+).
  Creates a scheduled task to run daily backups using upload.ps1.
  
.EXAMPLE
  .\setup-client.ps1
  
  Runs the interactive setup wizard to configure automated backups.
#>

[CmdletBinding()]
param()

# Requires Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Bakap Windows Client Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "This script will help you configure automated daily backups." -ForegroundColor White
Write-Host ""

# Function to read secure password
function Read-SecurePassword {
    param([string]$Prompt)
    
    $password = Read-Host -Prompt $Prompt -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    return $plainPassword
}

# Function to validate path exists
function Test-PathExists {
    param([string]$Path)
    return Test-Path -Path $Path
}

# Function to validate time format (HH:MM)
function Test-TimeFormat {
    param([string]$Time)
    return $Time -match '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$'
}

# Function to validate job name (alphanumeric and dash/underscore only)
function Test-JobName {
    param([string]$Name)
    return $Name -match '^[a-zA-Z0-9_-]+$'
}

Write-Host "Please provide the following information:" -ForegroundColor Yellow
Write-Host ""

# Collect configuration
do {
    $localPath = Read-Host "Enter the local path to backup (e.g., C:\Data)"
    if (-not (Test-PathExists $localPath)) {
        Write-Host "ERROR: Path does not exist. Please try again." -ForegroundColor Red
    }
} while (-not (Test-PathExists $localPath))

$server = Read-Host "Enter the backup server hostname or IP"

$username = Read-Host "Enter the SFTP username"

do {
    $password = Read-SecurePassword "Enter the SFTP password"
    $passwordConfirm = Read-SecurePassword "Confirm SFTP password"
    if ($password -ne $passwordConfirm) {
        Write-Host "ERROR: Passwords do not match. Please try again." -ForegroundColor Red
    }
} while ($password -ne $passwordConfirm)

$destPath = Read-Host "Enter the destination path on server (default: /uploads)"
if ([string]::IsNullOrWhiteSpace($destPath)) {
    $destPath = "/uploads"
}

do {
    $backupTime = Read-Host "Enter the backup time (HH:MM format, e.g., 02:00)"
    if (-not (Test-TimeFormat $backupTime)) {
        Write-Host "ERROR: Invalid time format. Use HH:MM (e.g., 02:00)" -ForegroundColor Red
    }
} while (-not (Test-TimeFormat $backupTime))

do {
    $jobName = Read-Host "Enter a name for this backup job (alphanumeric, no spaces)"
    if (-not (Test-JobName $jobName)) {
        Write-Host "ERROR: Job name can only contain letters, numbers, dashes, and underscores." -ForegroundColor Red
    }
} while (-not (Test-JobName $jobName))

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Configuration Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Local path:      $localPath" -ForegroundColor White
Write-Host "Backup server:   $server" -ForegroundColor White
Write-Host "Username:        $username" -ForegroundColor White
Write-Host "Remote path:     $destPath" -ForegroundColor White
Write-Host "Backup time:     $backupTime daily" -ForegroundColor White
Write-Host "Job name:        $jobName" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Is this correct? (y/n)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Setup cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Installing Backup Configuration" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Determine script directory and locate upload.ps1
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultUploadScript = Join-Path $scriptDir "upload.ps1"

if (Test-Path $defaultUploadScript) {
    Write-Host "Found upload.ps1 at: $defaultUploadScript" -ForegroundColor Green
    $useDefault = Read-Host "Use this location? (y/n)"
    if ($useDefault -eq 'y' -or $useDefault -eq 'Y') {
        $uploadScript = $defaultUploadScript
    } else {
        do {
            $uploadScript = Read-Host "Enter the full path to upload.ps1"
            if (-not (Test-Path $uploadScript)) {
                Write-Host "ERROR: File not found. Please try again." -ForegroundColor Red
            }
        } while (-not (Test-Path $uploadScript))
    }
} else {
    Write-Host "upload.ps1 not found in default location: $scriptDir" -ForegroundColor Yellow
    do {
        $uploadScript = Read-Host "Enter the full path to upload.ps1"
        if (-not (Test-Path $uploadScript)) {
            Write-Host "ERROR: File not found. Please try again." -ForegroundColor Red
        }
    } while (-not (Test-Path $uploadScript))
}

Write-Host "[OK] Using upload script: $uploadScript" -ForegroundColor Green

# Create directories
$bakupDir = "C:\Program Files\bakap-backup"
$credentialsDir = "C:\ProgramData\bakap-credentials"
$logsDir = "C:\ProgramData\bakap-logs"

if (-not (Test-Path $bakupDir)) {
    New-Item -ItemType Directory -Path $bakupDir -Force | Out-Null
    Write-Host "[OK] Created directory: $bakupDir" -ForegroundColor Green
}

if (-not (Test-Path $credentialsDir)) {
    New-Item -ItemType Directory -Path $credentialsDir -Force | Out-Null
    Write-Host "[OK] Created directory: $credentialsDir" -ForegroundColor Green
}

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "[OK] Created directory: $logsDir" -ForegroundColor Green
}

# Secure the credentials directory (only Administrators can access)
$acl = Get-Acl $credentialsDir
$acl.SetAccessRuleProtection($true, $false)
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($adminRule)
$acl.SetAccessRule($systemRule)
Set-Acl $credentialsDir $acl

# Create credentials file
$credFile = Join-Path $credentialsDir "$jobName.xml"
@{
    Server = $server
    Username = $username
    Password = $password
    DestPath = $destPath
    LocalPath = $localPath
} | Export-Clixml -Path $credFile
Write-Host "[OK] Created secure credentials file: $credFile" -ForegroundColor Green

# Create backup script
$backupScript = Join-Path $bakupDir "backup-$jobName.ps1"
$logFile = Join-Path $logsDir "bakap-$jobName.log"

$scriptContent = @"
# Bakap Backup Script - $jobName
# Auto-generated by setup-client.ps1
# Copyright (c) 2025 Yianni Bourkelis - MIT License

`$ErrorActionPreference = "Stop"
`$logFile = "$logFile"
`$credFile = "$credFile"
`$uploadScript = "$uploadScript"

# Function to write log with timestamp
function Write-Log {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "[$timestamp] `$Message"
    Write-Host `$logMessage
    Add-Content -Path `$logFile -Value `$logMessage
}

Write-Log "=========================================="
Write-Log "Bakap Backup Started - $jobName"
Write-Log "=========================================="

try {
    # Load credentials
    Write-Log "Loading credentials..."
    `$config = Import-Clixml -Path `$credFile
    
    # Run backup
    Write-Log "Starting upload: `$(`$config.LocalPath) -> `$(`$config.Server):`$(`$config.DestPath)"
    
    # Build upload command with optional WinSCP/pscp path
    `$uploadArgs = @(
        "-LocalPath", `$config.LocalPath,
        "-Server", `$config.Server,
        "-Username", `$config.Username,
        "-Password", `$config.Password,
        "-DestPath", `$config.DestPath
    )
    
    if (`$config.WinSCPPath -and (Test-Path `$config.WinSCPPath)) {
        `$uploadArgs += "-WinSCPPath"
        `$uploadArgs += `$config.WinSCPPath
        Write-Log "Using WinSCP at: `$(`$config.WinSCPPath)"
    } elseif (`$config.PscpPath -and (Test-Path `$config.PscpPath)) {
        Write-Log "Using pscp.exe at: `$(`$config.PscpPath)"
        # Note: upload.ps1 will find pscp.exe in PATH, but we log the path here for reference
    }
    
    & PowerShell.exe -ExecutionPolicy Bypass -File `$uploadScript @uploadArgs
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Log "Backup completed successfully"
    } else {
        Write-Log "ERROR: Backup failed with exit code `$LASTEXITCODE"
        exit `$LASTEXITCODE
    }
    
} catch {
    Write-Log "ERROR: `$(`$_.Exception.Message)"
    Write-Log "Stack trace: `$(`$_.ScriptStackTrace)"
    exit 1
}

Write-Log "=========================================="
Write-Log "Bakap Backup Finished"
Write-Log "=========================================="
"@

Set-Content -Path $backupScript -Value $scriptContent -Encoding UTF8
Write-Host "[OK] Created backup script: $backupScript" -ForegroundColor Green

# Create scheduled task
$taskName = "Bakap-Backup-$jobName"

# Parse time
$timeParts = $backupTime.Split(':')
$taskTime = Get-Date -Hour $timeParts[0] -Minute $timeParts[1] -Second 0

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Scheduled task '$taskName' already exists. Removing old task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$backupScript`""

# Create trigger (daily at specified time)
$trigger = New-ScheduledTaskTrigger -Daily -At $taskTime

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RunOnlyIfNetworkAvailable

# Register task (run as SYSTEM)
Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "NT AUTHORITY\SYSTEM" `
    -RunLevel Highest `
    -Description "Bakap automated backup for $jobName" | Out-Null

Write-Host "[OK] Created scheduled task: $taskName" -ForegroundColor Green

# Check for WinSCP or pscp in default locations and PATH
Write-Host ""
Write-Host "Checking for SFTP client (WinSCP or PuTTY)..." -ForegroundColor Yellow

$winscpPath = $null
$pscpPath = $null

# Check common WinSCP installation paths
$winscpDefaultPaths = @(
    "C:\Program Files\WinSCP\WinSCP.com",
    "C:\Program Files (x86)\WinSCP\WinSCP.com",
    "$env:ProgramFiles\WinSCP\WinSCP.com",
    "${env:ProgramFiles(x86)}\WinSCP\WinSCP.com"
)

foreach ($path in $winscpDefaultPaths) {
    if (Test-Path $path) {
        $winscpPath = $path
        Write-Host "[OK] Found WinSCP at: $winscpPath" -ForegroundColor Green
        break
    }
}

# If not found in default locations, check PATH
if (-not $winscpPath) {
    try {
        $winscpCmd = Get-Command winscp.com -ErrorAction SilentlyContinue
        if ($winscpCmd) {
            $winscpPath = $winscpCmd.Source
            Write-Host "[OK] Found WinSCP in PATH: $winscpPath" -ForegroundColor Green
        }
    } catch {}
}

# Check common PuTTY installation paths
$pscpDefaultPaths = @(
    "C:\Program Files\PuTTY\pscp.exe",
    "C:\Program Files (x86)\PuTTY\pscp.exe",
    "$env:ProgramFiles\PuTTY\pscp.exe",
    "${env:ProgramFiles(x86)}\PuTTY\pscp.exe"
)

foreach ($path in $pscpDefaultPaths) {
    if (Test-Path $path) {
        $pscpPath = $path
        Write-Host "[OK] Found PuTTY (pscp.exe) at: $pscpPath" -ForegroundColor Green
        break
    }
}

# If not found in default locations, check PATH
if (-not $pscpPath) {
    try {
        $pscpCmd = Get-Command pscp.exe -ErrorAction SilentlyContinue
        if ($pscpCmd) {
            $pscpPath = $pscpCmd.Source
            Write-Host "[OK] Found PuTTY (pscp.exe) in PATH: $pscpPath" -ForegroundColor Green
        }
    } catch {}
}

# If neither found, prompt user
if (-not $winscpPath -and -not $pscpPath) {
    Write-Host ""
    Write-Host "WARNING: Neither WinSCP nor PuTTY (pscp.exe) found automatically!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please choose an option:" -ForegroundColor Yellow
    Write-Host "  1. Specify path to WinSCP.com" -ForegroundColor White
    Write-Host "  2. Specify path to pscp.exe (PuTTY)" -ForegroundColor White
    Write-Host "  3. Skip (you'll need to install WinSCP or PuTTY before running backups)" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter choice (1-3)"
    
    if ($choice -eq '1') {
        do {
            $winscpPath = Read-Host "Enter the full path to WinSCP.com"
            if (-not (Test-Path $winscpPath)) {
                Write-Host "ERROR: File not found. Please try again or press Ctrl+C to skip." -ForegroundColor Red
            }
        } while (-not (Test-Path $winscpPath))
        Write-Host "[OK] Using WinSCP at: $winscpPath" -ForegroundColor Green
    } elseif ($choice -eq '2') {
        do {
            $pscpPath = Read-Host "Enter the full path to pscp.exe"
            if (-not (Test-Path $pscpPath)) {
                Write-Host "ERROR: File not found. Please try again or press Ctrl+C to skip." -ForegroundColor Red
            }
        } while (-not (Test-Path $pscpPath))
        Write-Host "[OK] Using PuTTY (pscp.exe) at: $pscpPath" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "WARNING: No SFTP client configured!" -ForegroundColor Yellow
        Write-Host "Please install one of the following before running backups:" -ForegroundColor Yellow
        Write-Host "  - WinSCP: https://winscp.net/" -ForegroundColor White
        Write-Host "  - PuTTY: https://www.chiark.greenend.org.uk/~sgtatham/putty/" -ForegroundColor White
        Write-Host ""
    }
}

# Save SFTP client path to credentials file if found
if ($winscpPath -or $pscpPath) {
    $config = Import-Clixml -Path $credFile
    if ($winscpPath) {
        $config['WinSCPPath'] = $winscpPath
    }
    if ($pscpPath) {
        $config['PscpPath'] = $pscpPath
    }
    $config | Export-Clixml -Path $credFile
    Write-Host "[OK] SFTP client path saved to configuration" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Backup job '$jobName' has been configured successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration details:" -ForegroundColor Yellow
Write-Host "  - Backup script:    $backupScript" -ForegroundColor White
Write-Host "  - Credentials:      $credFile" -ForegroundColor White
Write-Host "  - Log file:         $logFile" -ForegroundColor White
Write-Host "  - Schedule:         Daily at $backupTime" -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  - Test backup now:      PowerShell.exe -ExecutionPolicy Bypass -File `"$backupScript`"" -ForegroundColor White
Write-Host "  - View logs:            Get-Content `"$logFile`" -Tail 50" -ForegroundColor White
Write-Host "  - View scheduled task:  Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host "  - Run task manually:    Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host "  - Disable task:         Disable-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host ""

$testNow = Read-Host "Would you like to test the backup now? (y/n)"
if ($testNow -eq 'y' -or $testNow -eq 'Y') {
    Write-Host ""
    Write-Host "Running test backup..." -ForegroundColor Yellow
    Write-Host ""
    
    & PowerShell.exe -ExecutionPolicy Bypass -File $backupScript
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Test backup completed successfully!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Test backup failed. Check the log file for details:" -ForegroundColor Red
        Write-Host "  $logFile" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "Setup finished!" -ForegroundColor Green
