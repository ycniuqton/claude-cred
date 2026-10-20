# Install claude-cred as a command on Windows.
#
#   irm https://raw.githubusercontent.com/ycniuqton/claude-cred/main/install.ps1 | iex
#
# Installs to %LOCALAPPDATA%\Programs\claude-cred and adds it to your user PATH.
# Env override: $env:CLAUDE_CRED_REF = 'v1.0.0' to install a tag/branch instead of main.

& {
  $ErrorActionPreference = 'Stop'

  $repo   = 'ycniuqton/claude-cred'
  $ref    = if ($env:CLAUDE_CRED_REF) { $env:CLAUDE_CRED_REF } else { 'main' }
  $url    = "https://raw.githubusercontent.com/$repo/$ref/claude-cred.ps1"
  $root   = Join-Path $env:LOCALAPPDATA 'Programs\claude-cred'
  $libDir = Join-Path $root 'lib'

  # Windows PowerShell 5.1 may default to TLS 1.0, which GitHub rejects.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  New-Item -ItemType Directory -Force -Path $libDir | Out-Null
  $tmp = Join-Path $libDir 'claude-cred.ps1.download'
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
  if (-not (Select-String -LiteralPath $tmp -Pattern 'function Cmd-Load' -Quiet)) {
    Remove-Item -LiteralPath $tmp -Force
    throw "downloaded file doesn't look like claude-cred.ps1: $url"
  }
  Move-Item -LiteralPath $tmp (Join-Path $libDir 'claude-cred.ps1') -Force

  # The .ps1 lives in lib\ so only the .cmd shim is on PATH: PowerShell would
  # otherwise pick the .ps1 first and hit the default execution policy.
  $shim = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0lib\claude-cred.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n"
  [IO.File]::WriteAllText((Join-Path $root 'claude-cred.cmd'), $shim, (New-Object System.Text.ASCIIEncoding))

  # Edit the raw registry value so existing %VAR% entries stay unexpanded
  # ([Environment]::SetEnvironmentVariable would flatten them).
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  $path = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $parts = @($path -split ';' | Where-Object { $_ })
  if ($parts -notcontains $root) {
    $key.SetValue('Path', (($parts + $root) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    # Setting any user env var broadcasts WM_SETTINGCHANGE so new terminals see the PATH.
    [Environment]::SetEnvironmentVariable('CLAUDE_CRED_INSTALL_TMP', '1', 'User')
    [Environment]::SetEnvironmentVariable('CLAUDE_CRED_INSTALL_TMP', $null, 'User')
    Write-Host "Added $root to your user PATH"
  }
  $key.Close()
  if (($env:Path -split ';') -notcontains $root) { $env:Path = "$env:Path;$root" }

  Write-Host "Installed claude-cred ($ref) to $root"
  Write-Host "Run: claude-cred load <file.tar.gz>   (open a new terminal if the command isn't found)"
}
