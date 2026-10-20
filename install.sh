#!/usr/bin/env bash
# Install claude-cred as a command on Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/ycniuqton/claude-cred/main/install.sh | bash
#
# Env overrides:
#   CLAUDE_CRED_REF=v1.0.0          install a tag/branch instead of main
#   CLAUDE_CRED_BIN_DIR=/some/dir   install somewhere other than ~/.local/bin

set -euo pipefail

REPO="ycniuqton/claude-cred"
REF="${CLAUDE_CRED_REF:-main}"
BIN_DIR="${CLAUDE_CRED_BIN_DIR:-$HOME/.local/bin}"
URL="https://raw.githubusercontent.com/$REPO/$REF/claude-cred.sh"
DEST="$BIN_DIR/claude-cred"

die() { echo "error: $*" >&2; exit 1; }

mkdir -p "$BIN_DIR"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$tmp" || die "download failed: $URL"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp" "$URL" || die "download failed: $URL"
else
  die "need curl or wget"
fi

head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash' || die "downloaded file doesn't look like claude-cred.sh"

install -m 755 "$tmp" "$DEST"
echo "Installed $DEST ($REF)"

command -v python3 >/dev/null 2>&1 || echo "warning: python3 not found; claude-cred needs it to read/merge ~/.claude.json" >&2

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "Run: claude-cred export" ;;
  *)
    echo
    echo "$BIN_DIR is not on your PATH. Add it, e.g.:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    ;;
esac
