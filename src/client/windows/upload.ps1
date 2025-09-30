<#
.SYNOPSIS
  Upload a file or directory to the bakap SFTP server (Windows client).

.DESCRIPTION
  Compatible with Windows Server 2008 R2 and later (PowerShell 2.0+).
  Prefers WinSCP (WinSCP.com). If WinSCP is not installed, falls back to PuTTY's pscp.exe.
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

USAGE
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -DestPath uploads/ -ExpectedHostFingerprint 'SHA256:...'
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -DestPath uploads/ -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com' -Force
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -DestPath uploads/ -SkipIdentical

Notes:
- Install WinSCP and put WinSCP.com in PATH for best results: https://winscp.net/
- Alternatively install PuTTY (pscp.exe) in PATH.
#>

param(
  [Parameter(Mandatory=$true)][string]$LocalPath,
  [Parameter(Mandatory=$true)][string]$Username,
  [Parameter(Mandatory=$true)][string]$Password,
  [string]$DestPath = "uploads/",
  [string]$ExpectedHostFingerprint = "",
  [switch]$LogDebug,
  [switch]$Force,
  [string]$WinSCPPath = ""
)

# Normalize destination path: strip leading slashes/backslashes so the path is
# always relative to the user's chroot. If empty after trimming, use 'uploads'.
$DestPath = $DestPath.TrimStart('/','\')
if ([string]::IsNullOrEmpty($DestPath) -or [string]::IsNullOrEmpty($DestPath.Trim())) { $DestPath = 'uploads' }

$Server = "202.61.225.34"

function Write-Err([string]$m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $LocalPath)) {
    Write-Err "Local path does not exist: $LocalPath"
    exit 3
}

Write-Host "Uploading '$LocalPath' as user '$Username' to $Server:$DestPath"

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

  # Use synchronize for directories (incremental sync, no delete), put for files
  if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
    $putCmd = @"
synchronize local "$LocalPath" "$DestPath" -delete=no
"@
  } else {
    $putCmd = @"
put "$LocalPath" "$DestPath"
"@
  }

  # Build script file: open, optional pre-commands, put, exit
  $sb = "open sftp://$Username@${Server}/ -password=`"$Password`" $hostKeyOpt`r`n"
  if ($preCmds -ne "") { $sb += "$preCmds`r`n" }
  $sb += "$putCmd`r`n"
  $sb += "exit`r`n"
  Set-Content -Path $winscpScript -Value $sb -Encoding ASCII

  # Build WinSCP command; if Debug, request a log file
  if ($LogDebug.IsPresent) {
    $logFile = [System.IO.Path]::GetTempFileName()
    Write-Host "Debug mode: WinSCP raw log will be saved to $logFile"
    & $winscp "/log=$logFile" "/script=$winscpScript"
    $rc = $LASTEXITCODE
    Write-Host "WinSCP log: $logFile"
  } else {
    & $winscp "/script=$winscpScript"
    $rc = $LASTEXITCODE
  }
  Remove-Item -Force $winscpScript -ErrorAction SilentlyContinue
  if ($rc -ne 0) { Write-Err "WinSCP failed with exit code $rc"; exit $rc }
  Write-Host "Upload finished."
  exit 0
}

# Fallback: pscp (PuTTY's scp). This may or may not be available and scp may be disabled server-side.
$pscp = $null
try { $pscp = (Get-Command pscp.exe -ErrorAction SilentlyContinue).Source } catch { $pscp = $null }
if (-not $pscp) {
    $possible = @("$env:ProgramFiles\PuTTY\pscp.exe","$env:ProgramFiles(x86)\PuTTY\pscp.exe")
    foreach ($p in $possible) { if (Test-Path $p) { $pscp = $p; break } }
}

if ($pscp) {
    Write-Host "Using pscp: $pscp"
  # If Force, remove remote target first using sftp batch
  if ($Force.IsPresent) {
    $sftpBatch = [System.IO.Path]::GetTempFileName()
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      # remove remote directory and recreate
      $batch = @"
rm -r $DestPath
mkdir $DestPath
bye
"@
      Set-Content -Path $sftpBatch -Value $batch -Encoding ASCII
    } else {
      $batch = @"
rm $DestPath
bye
"@
      Set-Content -Path $sftpBatch -Value $batch -Encoding ASCII
    }
    # run sftp in batch mode (assumes sftp present)
    & sftp -b $sftpBatch "$Username@$Server" 2>$null
    Remove-Item -Force $sftpBatch -ErrorAction SilentlyContinue
  }

  if ($LogDebug.IsPresent) {
    $logFile = [System.IO.Path]::GetTempFileName()
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      & $pscp -r -pw $Password $LocalPath "$Username@$Server:$DestPath" 2>&1 | Tee-Object -FilePath $logFile
    } else {
      & $pscp -pw $Password $LocalPath "$Username@$Server:$DestPath" 2>&1 | Tee-Object -FilePath $logFile
    }
    $rc = $LASTEXITCODE
    Write-Host "pscp debug log: $logFile"
  } else {
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      & $pscp -r -pw $Password $LocalPath "$Username@$Server:$DestPath"
    } else {
      & $pscp -pw $Password $LocalPath "$Username@$Server:$DestPath"
    }
    $rc = $LASTEXITCODE
  }
  if ($rc -ne 0) { Write-Err "pscp failed with exit code $rc"; exit $rc }
  Write-Host "Upload finished."
  exit 0
}

Write-Err "Neither WinSCP.com nor pscp.exe found. Please install WinSCP (recommended) or PuTTY and ensure the executable is in PATH."
exit 4
