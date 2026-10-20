#!/usr/bin/env bash
# Export/load a Claude Code login (~/.claude/.credentials.json + the
# non-secret account identity block from ~/.claude.json) between machines
# you control.
#
# Usage:
#   claude-cred export [output.tar.gz]
#   claude-cred load   <input.tar.gz> [--keep]
#
# The tarball contains a LIVE ACCESS TOKEN. Treat it like a password:
#   - Move it only over SSH (scp/rsync over ssh, or `ssh ... | tar ...`).
#   - Never park it in a shared/world-readable path.
#   - `load` deletes the tarball after a successful import unless you
#     pass --keep; delete the export-side copy yourself too.

set -euo pipefail
umask 077

CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"
CREDS_FILE="$CLAUDE_DIR/.credentials.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

die() { echo "error: $*" >&2; exit 1; }

merge_oauth_account() {
  # $1 = path to oauthAccount.json (non-secret identity fields)
  python3 - "$1" "$CLAUDE_JSON" <<'PY'
import json, sys, time

oauth_path, claude_json_path = sys.argv[1], sys.argv[2]

with open(oauth_path) as f:
    block = json.load(f)

with open(claude_json_path) as f:
    doc = json.load(f)

block["profileFetchedAt"] = int(time.time() * 1000)
doc["oauthAccount"] = block

with open(claude_json_path, "w") as f:
    json.dump(doc, f, indent=2)
PY
}

extract_oauth_account() {
  # $1 = output path. Skips any key containing token/secret/key as a
  # defensive filter (the oauthAccount block is identity-only, not
  # auth material, but this keeps it that way if the schema ever grows).
  python3 - "$1" "$CLAUDE_JSON" <<'PY'
import json, sys

out_path, claude_json_path = sys.argv[1], sys.argv[2]

with open(claude_json_path) as f:
    doc = json.load(f)

acct = doc.get("oauthAccount")
if acct is None:
    print("no oauthAccount block in ~/.claude.json — skipping identity export", file=sys.stderr)
    sys.exit(0)

safe = {k: v for k, v in acct.items()
        if not any(s in k.lower() for s in ("token", "secret", "key"))}

with open(out_path, "w") as f:
    json.dump(safe, f, indent=2)
PY
}

cmd_export() {
  local out="${1:-claude-cred-$(date +%Y%m%d-%H%M%S).tar.gz}"

  [[ -f "$CREDS_FILE" ]] || die "$CREDS_FILE not found — is this box logged in?"

  local stage
  stage=$(mktemp -d)
  trap 'rm -rf "${stage:-}"' EXIT

  cp "$CREDS_FILE" "$stage/.credentials.json"
  chmod 600 "$stage/.credentials.json"

  if [[ -f "$CLAUDE_JSON" ]]; then
    extract_oauth_account "$stage/oauthAccount.json"
  fi

  tar -czf "$out" -C "$stage" .
  chmod 600 "$out"

  echo "Wrote $out"
  echo
  echo "This file contains a live access token. Transfer it over SSH only,"
  echo "e.g.: scp \"$out\" user@newhost:~/"
  echo "then delete it from THIS machine too once the transfer is confirmed."
}

cmd_load() {
  local in="${1:?usage: claude-cred load <input.tar.gz> [--keep]}"
  local keep="${2:-}"

  [[ -f "$in" ]] || die "$in not found"

  # Validate tarball contents before touching anything: only the two
  # known filenames, no path traversal / absolute paths.
  local entries
  entries=$(tar -tzf "$in")
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    case "$entry" in
      ./|.credentials.json|./.credentials.json|oauthAccount.json|./oauthAccount.json) ;;
      *) die "unexpected entry in tarball: $entry (refusing to extract)" ;;
    esac
  done <<< "$entries"

  mkdir -p "$BACKUP_DIR"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)

  if [[ -f "$CREDS_FILE" ]]; then
    cp "$CREDS_FILE" "$BACKUP_DIR/.credentials.json.bak.$stamp"
  fi
  if [[ -f "$CLAUDE_JSON" ]]; then
    cp "$CLAUDE_JSON" "$BACKUP_DIR/.claude.json.bak.$stamp"
  fi

  local stage
  stage=$(mktemp -d)
  trap 'rm -rf "${stage:-}"' EXIT
  tar -xzf "$in" -C "$stage"

  [[ -f "$stage/.credentials.json" ]] || die "tarball has no .credentials.json"
  mkdir -p "$CLAUDE_DIR"
  cp "$stage/.credentials.json" "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"
  echo "Installed $CREDS_FILE (backup: $BACKUP_DIR/.credentials.json.bak.$stamp)"

  if [[ -f "$stage/oauthAccount.json" && -f "$CLAUDE_JSON" ]]; then
    merge_oauth_account "$stage/oauthAccount.json"
    echo "Merged oauthAccount identity into $CLAUDE_JSON (backup: $BACKUP_DIR/.claude.json.bak.$stamp)"
  fi

  if [[ "$keep" != "--keep" ]]; then
    rm -f "$in"
    echo "Deleted $in"
  else
    echo "Kept $in (--keep passed) — delete it yourself once you're done."
  fi

  echo
  echo "Restart the 'claude' process (exit any running session and launch a"
  echo "fresh one) — a session already running keeps the tokens it started"
  echo "with in memory and won't pick this up until it's restarted."
}

main() {
  local mode="${1:-}"
  shift || true
  case "$mode" in
    export) cmd_export "$@" ;;
    load)   cmd_load "$@" ;;
    *) die "usage: $(basename "$0") {export [output.tar.gz] | load <input.tar.gz> [--keep]}" ;;
  esac
}

main "$@"
