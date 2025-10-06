<#
.SYNOPSIS
  Upload a file or directory to the bakap SFTP server (Windows client).

.DESCRIPTION
  Bakap Windows Upload Client
  Copyright (c) 2025 Yianni Bourkelis
  Licensed under the MIT License - see LICENSE file for details
  https://github.com/YiannisBourkelis/bakap
  
  Compatible with Windows Server 2008 R2 and later (PowerShell 2.0+).
  Requires WinSCP (WinSCP.com) for SFTP transfers with synchronization support.
  By default, skips upload if the remote file exists and has the same SHA-256 hash (for single files).
  For directories, uses incremental sync to resume partial transfers and skip identical files (based on size/time).
  Use -Force to overwrite or upload even if identical.

.PARAMETER LocalPath
  Local file or directory to upload.
.PARAMETER Username
  Remote username.
.PARAMETER Password
  Password for the user (will be passed to client; visible while running).
.PARAMETER DestPath
  Destination path relative to the user's chroot (default: uploads/).
.PARAMETER ExpectedHostFingerprint
  Optional expected host fingerprint (pass to WinSCP as-is for verification). Example: "ssh-ed25519 256 AAAA..." or "SHA256:..." depending on what you have.
.PARAMETER LogDebug
  Enable debug logging to a temporary file (shows WinSCP/pscp raw output).
.PARAMETER Force
  Force upload: overwrite existing remote files/directories and upload even if identical.
.PARAMETER WinSCPPath
  Path to WinSCP.com executable (if not in PATH).
.PARAMETER Server
  SFTP server hostname or IP address (required).

USAGE
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -Server 202.61.15.24 -DestPath uploads/ -ExpectedHostFingerprint 'SHA256:...'
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -Server 192.168.1.100 -DestPath uploads/ -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com' -Force

Notes:
- Install WinSCP and put WinSCP.com in PATH: https://winscp.net/
- WinSCP is required for synchronize functionality (incremental uploads).
#>

param(
  [Parameter(Mandatory=$true)][string]$LocalPath,
  [Parameter(Mandatory=$true)][string]$Username,
  [Parameter(Mandatory=$true)][string]$Password,
  [string]$DestPath = "uploads/",
  [string]$ExpectedHostFingerprint = "",
  [switch]$LogDebug,
  [switch]$Force,
  [string]$WinSCPPath = "",
  [Parameter(Mandatory=$true)][string]$Server
)

# Normalize destination path: strip leading slashes/backslashes so the path is
# always relative to the user's chroot. If empty after trimming, use 'uploads'.
$DestPath = $DestPath.TrimStart('/','\')
if ([string]::IsNullOrEmpty($DestPath) -or [string]::IsNullOrEmpty($DestPath.Trim())) { $DestPath = 'uploads' }

function Write-Err([string]$m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $LocalPath)) {
    Write-Err "Local path does not exist: $LocalPath"
    exit 3
}

Write-Host "Uploading '$LocalPath' as user '$Username' to ${Server}:$DestPath"

# Find WinSCP.com
$winscp = $null
# Use user-specified WinSCPPath if provided and validate it
if (-not ([string]::IsNullOrEmpty($WinSCPPath) -or [string]::IsNullOrEmpty($WinSCPPath.Trim()))) {
  if (Test-Path $WinSCPPath) {
    $winscp = $WinSCPPath
    # If .exe provided, try to use .com instead (console version)
    if ($winscp.EndsWith(".exe")) {
      $comPath = $winscp -replace "\.exe$", ".com"
      if (Test-Path $comPath) {
        $winscp = $comPath
      }
    }
  } else {
    Write-Err "Provided WinSCPPath not found: $WinSCPPath"
    exit 2
  }
}
if (-not $winscp) {
  try { $winscp = (Get-Command WinSCP.com -ErrorAction SilentlyContinue).Source } catch { $winscp = $null }
}
if (-not $winscp) {
  # try common install locations
  $possible = @("$env:ProgramFiles\WinSCP\WinSCP.com", "$env:ProgramFiles(x86)\WinSCP\WinSCP.com")
  foreach ($p in $possible) { if (Test-Path $p) { $winscp = $p; break } }
}

# If not Force and LocalPath is a file, check if remote file has same hash (only if WinSCP is available)
if (-not $Force.IsPresent -and $winscp -and -not ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer)) {
    # Compute local SHA-256 hash
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $localHash = [BitConverter]::ToString($sha256.ComputeHash([System.IO.File]::ReadAllBytes($LocalPath))).Replace("-", "").ToLower()
    $sha256.Dispose()

    # Run WinSCP to get remote checksum
    $checkScript = [System.IO.Path]::GetTempFileName()
    $checkSb = "open sftp://$Username@${Server}/ -password=`"$Password`" $hostKeyOpt`r`n"
    $checkSb += "checksum SHA-256 `"$DestPath`"`r`n"
    $checkSb += "exit`r`n"
    Set-Content -Path $checkScript -Value $checkSb -Encoding ASCII

    $checkOutput = & $winscp "/script=$checkScript" 2>&1
    $checkRc = $LASTEXITCODE
    Remove-Item -Force $checkScript -ErrorAction SilentlyContinue

    if ($checkRc -eq 0) {
        # Parse output: "SHA-256 checksum is <hash> for <file>"
        $match = $checkOutput | Select-String -Pattern "SHA-256 checksum is (\w+) for"
        if ($match) {
            $remoteHash = $match.Matches.Groups[1].Value.ToLower()
            if ($remoteHash -eq $localHash) {
                Write-Host "Remote file is identical (SHA-256 hash matches), skipping upload."
                exit 0
            }
        }
    }
    # If checksum failed (e.g., file not exist), proceed with upload
}

if ($winscp) {
    Write-Host "Using WinSCP: $winscp"
    # Build WinSCP script contents
  if ($ExpectedHostFingerprint -ne "") {
    $hostKeyOpt = "-hostkey=`"$ExpectedHostFingerprint`""
  } else {
    $hostKeyOpt = ""
  }

  # Prepare WinSCP script file
  $winscpScript = [System.IO.Path]::GetTempFileName()

  # If Force: remove remote target first (for directories remove recursively)
  $preCmds = ""
  if ($Force.IsPresent) {
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      # remove remote directory if exists
      $preCmds = @"
rm -r "$DestPath"
mkdir "$DestPath"
"@
    } else {
      $preCmds = @"
rm "$DestPath"
"@
    }
  }

  # Use synchronize for directories (incremental sync with delete), put for files
  if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
    $putCmd = @"
synchronize remote -delete "$LocalPath" "$DestPath"
"@
  } else {
    $putCmd = @"
put "$LocalPath" "$DestPath"
"@
  }

  # Build script file: open, optional pre-commands, put, close, exit
  $sb = "open sftp://$Username@${Server}/ -password=`"$Password`" $hostKeyOpt`r`n"
  if ($preCmds -ne "") { $sb += "$preCmds`r`n" }
  $sb += "$putCmd`r`n"
  $sb += "close`r`n"
  $sb += "exit`r`n"
  Set-Content -Path $winscpScript -Value $sb -Encoding ASCII

  # Build WinSCP command and monitor output to kill process if it hangs
  # Use Start-Job to run WinSCP and monitor with timeout
  $jobScript = {
    param($winscpPath, $scriptPath, $logPath)
    if ($logPath) {
      & $winscpPath "/log=$logPath" "/script=$scriptPath"
    } else {
      & $winscpPath "/script=$scriptPath"
    }
    $LASTEXITCODE
  }
  
  if ($LogDebug.IsPresent) {
    $logFile = [System.IO.Path]::GetTempFileName()
    Write-Host "Debug mode: WinSCP raw log will be saved to $logFile"
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $winscp,$winscpScript,$logFile
  } else {
    $logFile = $null
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $winscp,$winscpScript,$null
  }
  
  # Monitor job output for hang detection
  # Only trigger if we see "No session." followed by 5 seconds of silence
  $noSessionDetected = $false
  $noSessionTime = $null
  $hangTimeout = 5  # seconds to wait after "No session." before killing
  
  while ($job.State -eq 'Running') {
    $output = Receive-Job $job 2>&1
    if ($output) {
      foreach ($line in $output) {
        Write-Host $line
        # Check if output contains "No session."
        if ($line -match "No session\.") {
          $noSessionDetected = $true
          $noSessionTime = Get-Date
          Write-Host "Detected 'No session.' - monitoring for hang..."
        }
      }
    }
    
    # If "No session." was detected, check if we've had silence for hangTimeout seconds
    if ($noSessionDetected -and $noSessionTime) {
      $silenceDuration = ((Get-Date) - $noSessionTime).TotalSeconds
      if ($silenceDuration -gt $hangTimeout) {
        Write-Host "Process hung after 'No session.' message, terminating..."
        Stop-Job $job -ErrorAction SilentlyContinue
        Get-Process | Where-Object { $_.Name -like "*winscp*" } | ForEach-Object { 
          try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
        break
      }
    }
    
    Start-Sleep -Milliseconds 500
  }
  
  # Get any remaining output
  $output = Receive-Job $job 2>&1
  if ($output) {
    foreach ($line in $output) { Write-Host $line }
  }
  
  $rc = if ($job.State -eq 'Completed') { Receive-Job $job } else { 0 }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  
  if ($LogDebug.IsPresent -and $logFile) {
    Write-Host "WinSCP log: $logFile"
  }
  
  Remove-Item -Force $winscpScript -ErrorAction SilentlyContinue
  if ($rc -ne 0) { Write-Err "WinSCP failed with exit code $rc"; exit $rc }
  Write-Host "Upload finished."
  exit 0
}

Write-Err "WinSCP.com not found. Please install WinSCP and ensure WinSCP.com is in PATH or use -WinSCPPath parameter."
Write-Err "Download WinSCP from: https://winscp.net/"
exit 4
