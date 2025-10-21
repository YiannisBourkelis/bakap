<#
.SYNOPSIS
  Upload a file or directory to the termiNAS SFTP server (Windows client).

.DESCRIPTION
  termiNAS Windows Upload Client
  Copyright (c) 2025 Yianni Bourkelis
  Licensed under the MIT License - see LICENSE file for details
  https://github.com/YiannisBourkelis/terminas
  
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
.PARAMETER DeleteRemote
  For directory synchronization, delete remote files that don't exist locally (WARNING: USE WITH CAUTION).
.PARAMETER WinSCPPath
  Path to WinSCP.com executable (if not in PATH).
.PARAMETER Server
  SFTP server hostname or IP address (required).

USAGE
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -Server 202.61.15.24 -DestPath uploads/ -ExpectedHostFingerprint 'SHA256:...'
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -Server 192.168.1.100 -DestPath uploads/ -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com' -Force
  .\upload.ps1 -LocalPath C:\data\backup -Username test2 -Password 'pass' -Server 192.168.1.100 -DeleteRemote  # Sync directory and delete remote files not present locally

Notes:
- Install WinSCP and put WinSCP.com in PATH: https://winscp.net/
- WinSCP is required for synchronize functionality (incremental uploads).
- Use -DeleteRemote with CAUTION: it will remove remote files that don't exist locally during directory sync.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$LocalPath,
    [Parameter(Mandatory=$true)]
    [string]$Server,
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [string]$DestPath = "uploads",
    [string]$ExpectedHostFingerprint = "",
    [string]$WinSCPPath = "",
    [switch]$LogDebug,
    [switch]$Force,
    [switch]$DeleteRemote
)

# Get version from VERSION file in repository root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VersionFile = Join-Path $ScriptDir "..\..\VERSION"
if (Test-Path $VersionFile) {
    $VERSION = (Get-Content $VersionFile -Raw).Trim()
} else {
    $VERSION = "unknown"
}# Normalize destination path: strip leading slashes/backslashes so the path is
# always relative to the user's chroot. If empty after trimming, use 'uploads'.
$DestPath = $DestPath.TrimStart('/','\')
if ([string]::IsNullOrEmpty($DestPath) -or [string]::IsNullOrEmpty($DestPath.Trim())) { $DestPath = 'uploads' }

# Set up logging and cache directory in ProgramData (works for both user and SYSTEM)
# ProgramData is accessible to all users and SYSTEM account
$terminasDataDir = Join-Path $env:ProgramData "terminas"
if (-not (Test-Path $terminasDataDir)) {
    try {
        New-Item -ItemType Directory -Path $terminasDataDir -Force | Out-Null
    } catch {
        Write-Host "ERROR: Failed to create data directory: $terminasDataDir - $_" -ForegroundColor Red
        exit 5
    }
}
$logFile = Join-Path $terminasDataDir "upload_log.txt"
$hostKeyCacheDir = Join-Path $terminasDataDir "hostkeys"
$hostKeyCacheFile = Join-Path $hostKeyCacheDir "$Server.txt"
$ErrorActionPreference = "Continue"

function Write-Log([string]$msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] $msg"
    try {
        Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    } catch {}
    Write-Host $msg
}

function Write-Err([string]$m){ 
    Write-Log "ERROR: $m"
    Write-Host $m -ForegroundColor Red 
}

Write-Log "=========================================="
Write-Log "Backup script started"
Write-Log "Running as user: $env:USERNAME"
Write-Log "User domain: $env:USERDOMAIN"
Write-Log "Script path: $($MyInvocation.MyCommand.Path)"
Write-Log "Parameters:"
Write-Log "  LocalPath: $LocalPath"
Write-Log "  Username: $Username"
Write-Log "  Server: $Server"
Write-Log "  DestPath: $DestPath"
Write-Log "  WinSCPPath: $WinSCPPath"
Write-Log "  ExpectedHostFingerprint: $(if($ExpectedHostFingerprint){'<provided>'}else{'<not provided>'})"
Write-Log "  LogDebug: $($LogDebug.IsPresent)"
Write-Log "  Force: $($Force.IsPresent)"
Write-Log "  DeleteRemote: $($DeleteRemote.IsPresent)"
Write-Log "Host key cache: $hostKeyCacheFile"

if (-not (Test-Path -LiteralPath $LocalPath)) {
    Write-Err "Local path does not exist: $LocalPath"
    exit 3
}

Write-Log "Uploading '$LocalPath' as user '$Username' to ${Server}:$DestPath"

# Find WinSCP.com
Write-Log "Searching for WinSCP.com..."
$winscp = $null
# Use user-specified WinSCPPath if provided and validate it
if (-not ([string]::IsNullOrEmpty($WinSCPPath) -or [string]::IsNullOrEmpty($WinSCPPath.Trim()))) {
  Write-Log "Checking provided WinSCPPath: $WinSCPPath"
  if (Test-Path $WinSCPPath) {
    $winscp = $WinSCPPath
    Write-Log "Found WinSCP at provided path: $winscp"
    # If .exe provided, try to use .com instead (console version)
    if ($winscp.EndsWith(".exe")) {
      $comPath = $winscp -replace "\.exe$", ".com"
      if (Test-Path $comPath) {
        $winscp = $comPath
        Write-Log "Using .com version instead: $winscp"
      }
    }
  } else {
    Write-Err "Provided WinSCPPath not found: $WinSCPPath"
    exit 2
  }
}
if (-not $winscp) {
  Write-Log "Searching for WinSCP.com in PATH..."
  try { $winscp = (Get-Command WinSCP.com -ErrorAction SilentlyContinue).Source } catch { $winscp = $null }
  if ($winscp) { Write-Log "Found in PATH: $winscp" }
}
if (-not $winscp) {
  Write-Log "Searching in common install locations..."
  # try common install locations
  $possible = @("$env:ProgramFiles\WinSCP\WinSCP.com", "$env:ProgramFiles(x86)\WinSCP\WinSCP.com")
  foreach ($p in $possible) { 
    Write-Log "Checking: $p"
    if (Test-Path $p) { 
      $winscp = $p
      Write-Log "Found at: $winscp"
      break 
    }
  }
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
    Write-Log "Using WinSCP: $winscp"
    
    # Handle host fingerprint caching
    $hostKeyOpt = ""
    $captureFingerprint = $false
    
    if ($ExpectedHostFingerprint -ne "") {
        # User provided fingerprint explicitly - use it
        Write-Log "Using provided host fingerprint"
        $hostKeyOpt = "-hostkey=`"$ExpectedHostFingerprint`""
    } else {
        # Check if we have a cached fingerprint for this server
        Write-Log "Checking for cached fingerprint: $hostKeyCacheFile"
        if (Test-Path $hostKeyCacheFile) {
            $cachedFingerprint = Get-Content $hostKeyCacheFile -ErrorAction SilentlyContinue
            if ($cachedFingerprint) {
                Write-Log "Using cached host fingerprint for $Server"
                $hostKeyOpt = "-hostkey=`"$cachedFingerprint`""
            }
        } else {
            # First connection - verify we can write to cache directory before proceeding
            Write-Log "First connection to $Server - verifying cache directory is writable"
            
            # Ensure cache directory exists
            if (-not (Test-Path $hostKeyCacheDir)) {
                try {
                    New-Item -ItemType Directory -Path $hostKeyCacheDir -Force | Out-Null
                    Write-Log "Created host key cache directory: $hostKeyCacheDir"
                } catch {
                    Write-Err "Failed to create cache directory: $hostKeyCacheDir - $_"
                    Write-Err "Cannot cache host fingerprint. Please provide -ExpectedHostFingerprint parameter."
                    exit 5
                }
            }
            
            # Test write access
            $testFile = Join-Path $hostKeyCacheDir "test_write.tmp"
            try {
                Set-Content -Path $testFile -Value "test" -ErrorAction Stop
                Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
                Write-Log "Cache directory is writable, will capture and cache host fingerprint"
                $captureFingerprint = $true
            } catch {
                Write-Err "Cannot write to cache directory: $hostKeyCacheDir - $_"
                Write-Err "Host fingerprint cannot be cached. Please provide -ExpectedHostFingerprint parameter or fix permissions."
                exit 5
            }
        }
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

  # Use synchronize for directories (incremental sync), put for files
  # Only delete remote files if -DeleteRemote switch is specified
  if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
    $deleteFlag = if ($DeleteRemote) { "-delete " } else { "" }
    $putCmd = @"
synchronize remote $deleteFlag"$LocalPath" "$DestPath"
"@
  } else {
    $putCmd = @"
put "$LocalPath" "$DestPath"
"@
  }

  # Build script file: open, optional pre-commands, put, close, exit
  # If capturing fingerprint, add "-hostkey=`"*`"" to accept any key on first connection
  if ($captureFingerprint) {
    $sb = "open sftp://$Username@${Server}/ -password=`"$Password`" -hostkey=`"*`"`r`n"
  } else {
    $sb = "open sftp://$Username@${Server}/ -password=`"$Password`" $hostKeyOpt`r`n"
  }
  # Set binary transfer mode for reliable file transfers
  $sb += "option transfer binary`r`n"
  if ($preCmds -ne "") { $sb += "$preCmds`r`n" }
  $sb += "$putCmd`r`n"
  $sb += "close`r`n"
  $sb += "exit`r`n"
  Set-Content -Path $winscpScript -Value $sb -Encoding ASCII

  # Build WinSCP command - simple direct execution with & operator
  # Always create log file for fingerprint capture if needed
  if ($LogDebug.IsPresent -or $captureFingerprint) {
    $winscpLogFile = [System.IO.Path]::GetTempFileName()
    if ($LogDebug.IsPresent) {
      Write-Log "Debug mode: WinSCP raw log will be saved to $winscpLogFile"
    }
  } else {
    $winscpLogFile = $null
  }
  
  # Build arguments array
  if ($winscpLogFile) {
    $winscpArgs = "/console /log=`"$winscpLogFile`" /script=`"$winscpScript`""
  } else {
    $winscpArgs = "/console /script=`"$winscpScript`""
  }
  
  # Start WinSCP process and get PID
  Write-Log "Starting WinSCP process..."
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $winscp
  $psi.Arguments = $winscpArgs
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $winscpProc = [System.Diagnostics.Process]::Start($psi)
  $winscpPID = $winscpProc.Id
  Write-Log "Started WinSCP with PID: $winscpPID"
  
  # Monitor output for "No session." and kill if it hangs
  $hangTimeout = 3  # seconds to wait after "No session." before killing
  $noSessionFile = [System.IO.Path]::GetTempFileName()
  
  # Read output asynchronously and write "No session." detection to temp file
  $outAction = {
    if ($EventArgs.Data) {
      Write-Host $EventArgs.Data
      
      # Check for "No session." in output
      if ($EventArgs.Data -match "(?i)no\s+session") {
        # Signal detection by writing timestamp to temp file
        $timestamp = (Get-Date).ToString("o")
        Set-Content -Path $Event.MessageData -Value $timestamp -Force
      }
    }
  }
  
  $outEvent = Register-ObjectEvent -InputObject $winscpProc -EventName OutputDataReceived -Action $outAction -MessageData $noSessionFile
  $errEvent = Register-ObjectEvent -InputObject $winscpProc -EventName ErrorDataReceived -Action $outAction -MessageData $noSessionFile
  
  $winscpProc.BeginOutputReadLine()
  $winscpProc.BeginErrorReadLine()
  
  # Wait for process to exit or hang after "No session."
  $noSessionTime = $null
  $actualExitCode = 0  # Assume success if WinSCP completed its work
  while (-not $winscpProc.HasExited) {
    # Check if "No session." was detected by reading temp file
    if ((Test-Path $noSessionFile) -and $noSessionTime -eq $null) {
      $content = Get-Content $noSessionFile -ErrorAction SilentlyContinue
      if ($content) {
        $noSessionTime = Get-Date
        Write-Log "Detected 'No session.' message, monitoring for hang..."
      }
    }
    
    # If detected, check if timeout exceeded
    if ($noSessionTime -ne $null) {
      $silenceDuration = ((Get-Date) - $noSessionTime).TotalSeconds
      if ($silenceDuration -gt $hangTimeout) {
        Write-Host "Process hung after 'No session.' message (${silenceDuration}s), terminating PID $winscpPID..."
        Write-Log "Terminating hung WinSCP process PID $winscpPID"
        Write-Log "Note: 'No session.' indicates WinSCP completed successfully before hanging on prompt"
        # Since "No session." means WinSCP finished its work successfully,
        # we can safely assume exit code 0 before killing the hung process
        $actualExitCode = 0
        try {
          $winscpProc.Kill()
          Write-Log "Successfully terminated WinSCP PID $winscpPID"
        } catch {
          Write-Log "Warning: Failed to stop WinSCP process $winscpPID : $_"
        }
        break
      }
    }
    Start-Sleep -Milliseconds 500
  }
  
  # Clean up events and temp file
  Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue
  Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue
  Remove-Item -Path $noSessionFile -Force -ErrorAction SilentlyContinue
  
  # Get exit code - use actual code from process unless we killed it after successful completion
  $winscpProc.WaitForExit()
  $rc = $winscpProc.ExitCode
  $winscpProc.Dispose()
  
  # If we killed the process after "No session." (which means success), use our saved exit code
  if ($rc -eq -1 -and $actualExitCode -eq 0) {
    Write-Log "WinSCP was terminated after successful completion (overriding exit code -1 with 0)"
    $rc = $actualExitCode
  }
  
  Write-Log "WinSCP process exited with code: $rc"
  
  # If we captured fingerprint on first connection, extract and cache it
  if ($captureFingerprint -and $rc -eq 0 -and $winscpLogFile) {
    Write-Log "Attempting to extract host fingerprint from WinSCP log: $winscpLogFile"
    
    # Parse WinSCP log to extract the host key
    $logContent = Get-Content $winscpLogFile -ErrorAction SilentlyContinue
    if ($logContent) {
        Write-Log "WinSCP log file contains $($logContent.Count) lines"
        
        # WinSCP writes "Host key fingerprint is:" on one line, then the actual fingerprint on the next line
        # Find the line with the header, then get the next line
        $fingerprint = $null
        for ($i = 0; $i -lt $logContent.Count; $i++) {
            if ($logContent[$i] -match "Host key fingerprint is:") {
                Write-Log "Found fingerprint header at line $($i + 1)"
                # The actual fingerprint is on the next line
                if ($i + 1 -lt $logContent.Count) {
                    $nextLine = $logContent[$i + 1]
                    Write-Log "Next line: $nextLine"
                    
                    # Extract fingerprint from the next line
                    # Format: ". 2025-10-07 17:13:56.723 ssh-ed25519 255 SHA256:..."
                    # We want everything after the timestamp, but without SHA256: prefix
                    if ($nextLine -match "\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+(.+)") {
                        $fingerprint = $matches[1].Trim()
                        Write-Log "Extracted fingerprint: $fingerprint"
                        
                        # Remove SHA256: prefix if present (WinSCP expects fingerprint without it)
                        # When WinSCP compares keys, it reports them as "ssh-ed25519 255 <hash>" (without SHA256:)
                        # But in the log it shows "ssh-ed25519 255 SHA256:<hash>"
                        $fingerprint = $fingerprint -replace '(\s+)SHA256:', '$1'
                        Write-Log "Normalized fingerprint (SHA256: prefix removed): $fingerprint"
                    } else {
                        Write-Log "WARNING: Could not extract fingerprint from next line"
                    }
                }
                break
            }
        }
        
        if ($fingerprint) {
            # Ensure cache directory exists
            if (-not (Test-Path $hostKeyCacheDir)) {
                Write-Log "Creating host key cache directory: $hostKeyCacheDir"
                New-Item -ItemType Directory -Path $hostKeyCacheDir -Force | Out-Null
            }
            
            # Save fingerprint to cache file
            Write-Log "Saving fingerprint to: $hostKeyCacheFile"
            Set-Content -Path $hostKeyCacheFile -Value $fingerprint -Force
            Write-Log "Cached host fingerprint for $Server : $fingerprint"
            Write-Log "Future connections will verify against this fingerprint."
        } else {
            Write-Err "SECURITY ERROR: Could not extract host fingerprint from WinSCP log"
            Write-Log "Showing lines containing 'fingerprint' or 'key' (case-insensitive):"
            $logContent | Select-String -Pattern "(fingerprint|host key)" -CaseSensitive:$false | Select-Object -First 10 | ForEach-Object { Write-Log "  $_" }
            Write-Err "Unable to cache host key for future verification. This is a security risk."
            Write-Err "To proceed, you can either:"
            Write-Err "  1. Manually provide -ExpectedHostFingerprint parameter with the correct fingerprint"
            Write-Err "  2. Check WinSCP log and report this issue"
            if ($LogDebug.IsPresent -and $winscpLogFile) {
                Write-Log "WinSCP log file: $winscpLogFile"
            }
            Write-Log "Script exiting with code 6 (fingerprint extraction failed)"
            Write-Log "=========================================="
            exit 6
        }
    } else {
        Write-Err "SECURITY ERROR: WinSCP log file is empty or could not be read"
        Write-Err "Cannot verify host fingerprint for caching. This is a security risk."
        Write-Err "Please provide -ExpectedHostFingerprint parameter for secure connections."
        Write-Log "Script exiting with code 6 (fingerprint extraction failed)"
        Write-Log "=========================================="
        exit 6
    }
  } elseif ($captureFingerprint) {
    Write-Log "WARNING: Fingerprint capture was enabled but conditions not met:"
    Write-Log "  captureFingerprint: $captureFingerprint"
    Write-Log "  rc (exit code): $rc"
    Write-Log "  winscpLogFile: $(if($winscpLogFile){'exists'}else{'null'})"
  }
    
  # Clean up temporary log file unless in debug mode
  if (-not $LogDebug.IsPresent -and $winscpLogFile) {
      Write-Log "Cleaning up temporary WinSCP log file"
      Remove-Item -Force $winscpLogFile -ErrorAction SilentlyContinue
  } elseif ($LogDebug.IsPresent -and $winscpLogFile) {
      Write-Log "Debug mode: WinSCP log preserved at $winscpLogFile"
  }
  
  Remove-Item -Force $winscpScript -ErrorAction SilentlyContinue
  if ($rc -ne 0) { 
    Write-Err "WinSCP failed with exit code $rc"
    Write-Log "Script exiting with code $rc"
    exit $rc 
  }
  Write-Log "Upload finished successfully."
  Write-Log "=========================================="
  exit 0
}

Write-Err "WinSCP.com not found. Please install WinSCP and ensure WinSCP.com is in PATH or use -WinSCPPath parameter."
Write-Err "Download WinSCP from: https://winscp.net/"
Write-Log "Script exiting with code 4 (WinSCP not found)"
Write-Log "=========================================="
exit 4
