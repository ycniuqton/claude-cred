# claude-cred

Move your own Claude Code login from one machine to another without signing in again.

- `claude-cred.sh` (Linux): `export` packs your login into a `.tar.gz`. `load` imports one on another Linux machine.
- `claude-cred.ps1` (Windows): `load` imports a `.tar.gz` made by `claude-cred.sh export`.

Supported directions: Linux → Linux and Linux → Windows.

## What gets copied

| File in the tarball | Source | Installed to |
|---|---|---|
| `.credentials.json` | `~/.claude/.credentials.json` | `~/.claude/.credentials.json` (Windows: `%USERPROFILE%\.claude\.credentials.json`) |
| `oauthAccount.json` | the `oauthAccount` block of `~/.claude.json` (identity only; keys containing `token`, `secret` or `key` are dropped) | merged into `~/.claude.json` (Windows: `%USERPROFILE%\.claude.json`) |

No other settings are touched.

## Install

**Linux** (needs `bash`, `tar`, `python3`, and `curl` or `wget`):

```bash
curl -fsSL https://raw.githubusercontent.com/ycniuqton/claude-cred/main/install.sh | bash
```

This installs the command to `~/.local/bin/claude-cred`. If that folder isn't on your PATH, the installer tells you how to add it.

**Windows** (PowerShell; needs Windows 10 1803 or later for the built-in `tar.exe`):

```powershell
irm https://raw.githubusercontent.com/ycniuqton/claude-cred/main/install.ps1 | iex
```

This installs to `%LOCALAPPDATA%\Programs\claude-cred` and adds that folder to your user PATH. Open a new terminal afterwards. The command works in both PowerShell and cmd.

To install a specific version, set `CLAUDE_CRED_REF` first, e.g. `CLAUDE_CRED_REF=v1.1.0` (bash) or `$env:CLAUDE_CRED_REF='v1.1.0'` (PowerShell). Running the installer again updates the command.

## Usage

### 1. Export on Linux

```bash
claude-cred export            # writes claude-cred-YYYYMMDD-HHMMSS.tar.gz in the current folder
```

### 2. Copy it over SSH

```bash
scp user@linux-host:~/claude-cred-*.tar.gz .
```

Then delete the tarball on the Linux machine.

### 3. Load on the other machine (Windows or Linux)

```
claude-cred load claude-cred-YYYYMMDD-HHMMSS.tar.gz [--keep]
```

### 4. Restart Claude Code

Exit any running `claude` session and start a new one. Run `/status` to check the account.

## What `load` does

1. Refuses the tarball if it contains anything other than `.credentials.json` and `oauthAccount.json` (no paths, no links).
2. Backs up your current files to `~/.claude/backups/` with a timestamp.
3. Installs `.credentials.json` and restricts it to your user (`chmod 600` on Linux, an `icacls` ACL on Windows).
4. Merges the `oauthAccount` block into `.claude.json`. If `.claude.json` doesn't exist yet, run `claude` once first.
5. Deletes the tarball, unless you pass `--keep`.

To undo, copy the backups from `~/.claude/backups/` back into place.

## Security

The tarball contains a **live access token and refresh token**. Treat it like a password:

- Move it over SSH only. Don't email it, put it in chat or cloud storage, or commit it. The `.gitignore` here blocks `*.tar.gz`.
- Delete it on both machines when you're done.
- If it leaks, log out of Claude Code on that account (or log in again) to invalidate the token.

Use this only for **your own** account on **machines you control**. Sharing a Claude account with other people is against Anthropic's terms.

## Notes

- Both machines may end up sharing one refresh token. If one machine refreshes it, the other can get logged out. If that happens, log in there again or import a fresh export.
- On macOS, Claude Code stores the login in the Keychain, not in `.credentials.json`, so these scripts don't support macOS.

## Uninstall

- **Linux:** `rm ~/.local/bin/claude-cred`
- **Windows:** delete `%LOCALAPPDATA%\Programs\claude-cred`, then remove it from your user PATH (Settings → System → About → Advanced system settings → Environment Variables).

## License

MIT
