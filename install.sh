#!/usr/bin/env bash
set -Eeuo pipefail

REPO="OfficialOnePesewa/op-vps-optimizer"
BRANCH="main"
INSTALL_DIR="/opt/op-vps-optimizer"
BIN_DIR="/usr/local/sbin"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this installer as root:"
    echo "curl -fsSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/install.sh | sudo bash"
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify this operating system."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "Unsupported operating system: ${ID:-unknown}"
        echo "This installer supports Debian and Ubuntu."
        exit 1
        ;;
esac

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required."
    exit 1
fi

for command_name in curl tar install; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name"
        echo "Install it using your distribution package manager, then retry."
        exit 1
    fi
done

ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

echo "Downloading OP VPS Optimizer..."
curl -fL --retry 3 "$ARCHIVE_URL" -o "$TMP_DIR/project.tar.gz"

mkdir -p "$TMP_DIR/source"
tar -xzf "$TMP_DIR/project.tar.gz" -C "$TMP_DIR/source" --strip-components=1

if [[ ! -f "$TMP_DIR/source/scripts/op-vps-optimizer" ]]; then
    echo "Project archive is incomplete. Installation cancelled."
    exit 1
fi

echo "Installing project files..."
mkdir -p "$INSTALL_DIR" "$BIN_DIR" /etc/op-badvpn

cp -a "$TMP_DIR/source/." "$INSTALL_DIR/"

install -m 0755 "$INSTALL_DIR/scripts/op-vps-optimizer" \
    "$BIN_DIR/op-vps-optimizer"

install -m 0755 "$INSTALL_DIR/scripts/optimize.sh" \
    "$INSTALL_DIR/scripts/status.sh" \
    "$INSTALL_DIR/scripts/rollback.sh" \
    "$INSTALL_DIR/scripts/install-badvpn.sh" \
    "$INSTALL_DIR/scripts/"

if [[ -f "$INSTALL_DIR/systemd/op-badvpn-udpgw.service" ]]; then
    install -m 0644 "$INSTALL_DIR/systemd/op-badvpn-udpgw.service" \
        /etc/systemd/system/op-badvpn-udpgw.service
    systemctl daemon-reload
fi

echo "Applying network optimization..."
"$BIN_DIR/op-vps-optimizer" apply

echo
echo "OP VPS Optimizer installation finished."
echo
echo "Available commands:"
echo "  sudo op-vps-optimizer apply"
echo "  sudo op-vps-optimizer status"
echo "  sudo op-vps-optimizer rollback"
echo "  sudo op-vps-optimizer install-badvpn"
