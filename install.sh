#!/usr/bin/env bash
# 📄 install.sh - OP VPS Optimizer bootstrap (v2.0.0)
# One-liner:
# curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | sudo bash
set -eo pipefail

REPO="OfficialOnePesewa/op-vps-optimizer"
BRANCH="main"
INSTALL_DIR="/opt/op-vps-optimizer"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(id -u)" -eq 0 ] || { echo "❌ Run as root: curl ... | sudo bash"; exit 1; }

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  echo "📦 Installing curl and tar..."
  apt-get update -y -qq && apt-get install -y -qq curl tar ca-certificates
fi

echo "⬇️  Downloading OP VPS Optimizer..."
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'op-vps-optimizer-*' | head -n1)"
[ -n "$SRC" ] || { echo "❌ Download failed. Check your internet connection."; exit 1; }

echo "📁 Installing to $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$SRC"/. "$INSTALL_DIR"/
chmod +x "$INSTALL_DIR"/scripts/*.sh

ln -sf "$INSTALL_DIR/scripts/optimize.sh" /usr/local/bin/op-optimize
ln -sf "$INSTALL_DIR/scripts/status.sh"   /usr/local/bin/op-status
ln -sf "$INSTALL_DIR/scripts/rollback.sh" /usr/local/bin/op-rollback

# Load shared helpers (banner, detection, success message)
. "$INSTALL_DIR/lib/detect.sh"
op_banner
echo
op_show_system
echo

if "$INSTALL_DIR/scripts/optimize.sh"; then
  echo
  op_thanks
else
  echo
  echo "❌ Installation did not finish. Run 'sudo op-rollback' to restore your settings."
  exit 1
fi
