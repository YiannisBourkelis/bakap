<#
.SYNOPSIS
  Upload a file or directory to the bakap SFTP server (Windows client).

.DESCRIPTION
  Compatible with Windows Server 2008 R2 and later (PowerShell 2.0+).
  Prefers WinSCP (WinSCP.com). If WinSCP is not installed, falls back to PuTTY's pscp.exe.

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

USAGE
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -DestPath uploads/ -ExpectedHostFingerprint 'SHA256:...'
  .\upload.ps1 -LocalPath C:\path\file.sql.gz -Username test2 -Password 'pass' -DestPath uploads/ -WinSCPPath 'C:\Program Files\WinSCP\WinSCP.com'

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
  [switch]$Debug,
  [switch]$Force,
  [string]$WinSCPPath = ""
)

# Normalize destination path: strip leading slashes/backslashes so the path is
# always relative to the user's chroot. If empty after trimming, use 'uploads'.
$DestPath = $DestPath.TrimStart('/','\')
if ([string]::IsNullOrWhiteSpace($DestPath)) { $DestPath = 'uploads' }

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
if ([string]::IsNullOrWhiteSpace($WinSCPPath) -eq $false) {
  if (Test-Path $WinSCPPath) {
    $winscp = $WinSCPPath
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

if ($winscp) {
    Write-Host "Using WinSCP: $winscp"
    # Build WinSCP script contents
  if ($ExpectedHostFingerprint -ne "") {
    $hostKeyOpt = "-hostkey=`"$ExpectedHostFingerprint`""
  } else {
    $hostKeyOpt = ""
  }

  # Prepare WinSCP script file
  $winscpScript = New-TemporaryFile

  # If Force: remove remote target first (for directories remove recursively)
  $preCmds = ""
  if ($Force.IsPresent) {
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      # remove remote directory if exists
      $preCmds = "rm -r \"$DestPath\"; mkdir \"$DestPath\"; "
    } else {
      $preCmds = "rm \"$DestPath\"; "
    }
  }

  # Use recursive put for directories
  if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
    $putCmd = "put -r \"$LocalPath\" \"$DestPath\""
  } else {
    $putCmd = "put \"$LocalPath\" \"$DestPath\""
  }

  # Build script file: open, optional pre-commands, put, exit
  $sb = "open sftp://$Username:$Password@${Server}/ $hostKeyOpt`r`n"
  if ($preCmds -ne "") { $sb += "$preCmds`r`n" }
  $sb += "$putCmd`r`n"
  $sb += "exit`r`n"
  Set-Content -Path $winscpScript -Value $sb -Encoding ASCII

  # Build WinSCP command; if Debug, request a log file
  if ($Debug.IsPresent) {
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
    $sftpBatch = New-TemporaryFile
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
    sftp -b $sftpBatch "$Username@$Server" 2>$null || true
    Remove-Item -Force $sftpBatch -ErrorAction SilentlyContinue
  }

  if ($Debug.IsPresent) {
    $logFile = [System.IO.Path]::GetTempFileName()
    if ((Test-Path -LiteralPath $LocalPath) -and (Get-Item $LocalPath).PSIsContainer) {
      & $pscp -r -pw $Password $LocalPath "$Username@$Server:$DestPath" *>&1 | Tee-Object -FilePath $logFile
    } else {
      & $pscp -pw $Password $LocalPath "$Username@$Server:$DestPath" *>&1 | Tee-Object -FilePath $logFile
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
