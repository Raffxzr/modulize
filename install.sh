#!/usr/bin/env bash
# Install modulize into a prefix without touching the source checkout.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
SHARE_DIR="${SHARE_DIR:-$PREFIX/share/modulize}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"

info() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v zip >/dev/null 2>&1 || fail "'zip' is required"
[[ -f "$ROOT_DIR/modulize" ]] || fail "modulize entrypoint not found"

info "Installing to $SHARE_DIR"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR" "$BIN_DIR"

cp -R "$ROOT_DIR/modulize" "$ROOT_DIR/lib" "$ROOT_DIR/templates" "$SHARE_DIR/"
cp "$ROOT_DIR/README.md" "$ROOT_DIR/CHANGELOG.md" "$ROOT_DIR/LICENSE" "$SHARE_DIR/"
chmod 0755 "$SHARE_DIR/modulize"

ln -sfn "$SHARE_DIR/modulize" "$BIN_DIR/modulize"

info "Linked $BIN_DIR/modulize"
"$BIN_DIR/modulize" version

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf '\nAdd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
esac
