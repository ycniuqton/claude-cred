# Load a Claude Code login exported on Linux by claude-cred.sh into this
# Windows machine (%USERPROFILE%\.claude\.credentials.json + the non-secret
# oauthAccount identity block merged into %USERPROFILE%\.claude.json).
#
# Usage (export on Ubuntu with claude-cred.sh, then on Windows):
#   claude-cred load <input.tar.gz> [--keep]
#
# The tarball contains a LIVE ACCESS TOKEN. Treat it like a password:
#   - Move it only over SSH (scp from Windows' built-in OpenSSH client).
#   - `load` deletes the tarball after a successful import unless you
#     pass --keep; delete the export-side copy yourself too.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$UserHome   = $env:USERPROFILE
$ClaudeDir  = Join-Path $UserHome '.claude'
$ClaudeJson = Join-Path $UserHome '.claude.json'
$CredsFile  = Join-Path $ClaudeDir '.credentials.json'
$BackupDir  = Join-Path $ClaudeDir 'backups'

# Use Windows' bundled bsdtar, not a Git/MSYS tar that may be earlier on PATH
# and mis-handle C:\ paths.
$Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $Tar)) { $Tar = 'tar' }

# Node's JSON.parse rejects a BOM, so never let PowerShell add one.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Die([string]$msg) {
  [Console]::Error.WriteLine("error: $msg")
  exit 1
}

function Restrict-ToCurrentUser([string]$path) {
  # Windows equivalent of chmod 600: drop inherited ACEs, grant only us.
  & icacls $path /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Warning "could not tighten ACL on $path" }
}

function New-JsonSerializer {
  # JavaScriptSerializer instead of ConvertFrom-Json: PS 5.1's parser treats
  # keys case-insensitively and chokes on ~/.claude.json "projects" entries
  # like "C:/x" vs "c:/x"; ConvertTo-Json also truncates at depth 2 by default.
  Add-Type -AssemblyName System.Web.Extensions
  $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $s.MaxJsonLength = [int]::MaxValue
  $s.RecursionLimit = 1000
  return $s
}

function Merge-OAuthAccount([string]$oauthPath) {
  $ser   = New-JsonSerializer
  $block = $ser.DeserializeObject([IO.File]::ReadAllText($oauthPath, $Utf8NoBom))
  $doc   = $ser.DeserializeObject([IO.File]::ReadAllText($ClaudeJson, $Utf8NoBom))
  if ($block -isnot [System.Collections.IDictionary]) { Die "oauthAccount.json is not a JSON object" }
  if ($doc -isnot [System.Collections.IDictionary]) { Die "$ClaudeJson is not a JSON object" }

  $block['profileFetchedAt'] = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $doc['oauthAccount'] = $block

  [IO.File]::WriteAllText($ClaudeJson, $ser.Serialize($doc), $Utf8NoBom)
}

function Cmd-Load([string[]]$rest) {
  $in = $null
  $keep = $false
  foreach ($a in $rest) {
    if ($a -eq '--keep' -or $a -eq '-keep') { $keep = $true }
    elseif (-not $in) { $in = $a }
    else { Die "unexpected argument: $a" }
  }
  if (-not $in) { Die "usage: claude-cred load <input.tar.gz> [--keep]" }
  if (-not (Test-Path -LiteralPath $in -PathType Leaf)) { Die "$in not found" }
  $in = (Resolve-Path -LiteralPath $in).ProviderPath

  # Validate tarball contents before touching anything: only the two
  # known filenames, no path traversal / absolute paths, no links.
  $entries = & $Tar -tzf $in
  if ($LASTEXITCODE -ne 0) { Die "cannot read $in as a .tar.gz" }
  foreach ($entry in $entries) {
    if (-not $entry) { continue }
    if ($entry -cnotin './', '.credentials.json', './.credentials.json', 'oauthAccount.json', './oauthAccount.json') {
      Die "unexpected entry in tarball: $entry (refusing to extract)"
    }
  }
  foreach ($line in (& $Tar -tvzf $in)) {
    if ($line -and $line[0] -ne '-' -and $line[0] -ne 'd') {
      Die "non-regular entry in tarball: $line (refusing to extract)"
    }
  }

  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $credsBak = Join-Path $BackupDir ".credentials.json.bak.$stamp"
  $jsonBak  = Join-Path $BackupDir ".claude.json.bak.$stamp"

  if (Test-Path -LiteralPath $CredsFile) { Copy-Item -LiteralPath $CredsFile $credsBak; Restrict-ToCurrentUser $credsBak }
  if (Test-Path -LiteralPath $ClaudeJson) { Copy-Item -LiteralPath $ClaudeJson $jsonBak }

  $stage = Join-Path ([IO.Path]::GetTempPath()) ("claude-cred-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage | Out-Null
  Restrict-ToCurrentUser $stage
  try {
    & $Tar -xzf $in -C $stage
    if ($LASTEXITCODE -ne 0) { Die "failed to extract $in" }

    $stagedCreds = Join-Path $stage '.credentials.json'
    $stagedOauth = Join-Path $stage 'oauthAccount.json'
    if (-not (Test-Path -LiteralPath $stagedCreds)) { Die "tarball has no .credentials.json" }

    New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
    # Byte-for-byte copy; the credentials format is the same on Linux and Windows.
    Copy-Item -LiteralPath $stagedCreds $CredsFile -Force
    Restrict-ToCurrentUser $CredsFile
    Write-Host "Installed $CredsFile (backup: $credsBak)"

    if (Test-Path -LiteralPath $stagedOauth) {
      if (Test-Path -LiteralPath $ClaudeJson) {
        Merge-OAuthAccount $stagedOauth
        Write-Host "Merged oauthAccount identity into $ClaudeJson (backup: $jsonBak)"
      } else {
        Write-Warning "$ClaudeJson not found - skipped identity merge. Run 'claude' once, exit, then re-run load."
      }
    }
  } finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
  }

  if (-not $keep) {
    Remove-Item -LiteralPath $in -Force
    Write-Host "Deleted $in"
  } else {
    Write-Host "Kept $in (--keep passed) - delete it yourself once you're done."
  }

  Write-Host ""
  Write-Host "Restart the 'claude' process (exit any running session and launch a"
  Write-Host "fresh one) - a session already running keeps the tokens it started"
  Write-Host "with in memory and won't pick this up until it's restarted."
}

$mode = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { [string[]]$args[1..($args.Count - 1)] } else { @() }
switch ($mode) {
  'load'   { Cmd-Load $rest }
  'export' { Die "export is not supported on Windows; run 'claude-cred.sh export' on the Linux box" }
  default  { Die "usage: claude-cred load <input.tar.gz> [--keep]" }
}
