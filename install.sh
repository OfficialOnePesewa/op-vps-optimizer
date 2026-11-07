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

# Root check
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please log in as root."
    exit 1
fi

# Detect Debian or Ubuntu
if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot identify operating system."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "ERROR: Debian or Ubuntu is required."
        exit 1
        ;;
esac

echo "======================================"
echo "       OP VPS OPTIMIZER"
echo "======================================"
echo "System: ${PRETTY_NAME:-Unknown}"
echo "Kernel: $(uname -r)"
echo

# Automatically install missing download dependencies.
export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Checking download dependencies..."

if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: APT package manager not found."
    exit 1
fi

apt-get update

PACKAGES=()

command -v curl >/dev/null 2>&1 || PACKAGES+=(curl)
command -v wget >/dev/null 2>&1 || PACKAGES+=(wget)
command -v tar >/dev/null 2>&1 || PACKAGES+=(tar)

dpkg -s ca-certificates >/dev/null 2>&1 || PACKAGES+=(ca-certificates)

if [[ "${#PACKAGES[@]}" -gt 0 ]]; then
    echo "Installing missing packages: ${PACKAGES[*]}"
    apt-get install -y "${PACKAGES[@]}"
fi

# Verify download tools.
if ! command -v curl >/dev/null 2>&1 && \
   ! command -v wget >/dev/null 2>&1; then
    echo "ERROR: Could not install curl or wget."
    exit 1
fi

# Download repository.
echo
echo "[2/5] Downloading repository..."

ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
ARCHIVE="$TMP_DIR/project.tar.gz"

if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 \
        "$ARCHIVE_URL" -o "$ARCHIVE"
else
    wget -O "$ARCHIVE" "$ARCHIVE_URL"
fi

# Extract repository.
echo
echo "[3/5] Extracting project..."

mkdir -p "$TMP_DIR/source"

tar -xzf "$ARCHIVE" \
    -C "$TMP_DIR/source" \
    --strip-components=1

# Validate required files.
for file in \
    scripts/op-vps-optimizer \
    scripts/optimize.sh \
    scripts/status.sh \
    scripts/rollback.sh \
    scripts/install-badvpn.sh \
    systemd/op-badvpn-udpgw.service
do
    if [[ ! -f "$TMP_DIR/source/$file" ]]; then
        echo "ERROR: Missing repository file: $file"
        exit 1
    fi
done

# Install project.
echo
echo "[4/5] Installing project..."

mkdir -p "$INSTALL_DIR" "$BIN_DIR" /etc/op-badvpn

cp -a "$TMP_DIR/source/." "$INSTALL_DIR/"

# Set executable permissions automatically.
chmod 0755 "$INSTALL_DIR/scripts/"*.sh
chmod 0755 "$INSTALL_DIR/scripts/op-vps-optimizer"

install -m 0755 \
    "$INSTALL_DIR/scripts/op-vps-optimizer" \
    "$BIN_DIR/op-vps-optimizer"

# Install systemd service definition.
install -m 0644 \
    "$INSTALL_DIR/systemd/op-badvpn-udpgw.service" \
    /etc/systemd/system/op-badvpn-udpgw.service

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
fi

# Apply network optimization.
echo
echo "[5/5] Applying network optimization..."

"$BIN_DIR/op-vps-optimizer" apply

echo
echo "======================================"
echo "     INSTALLATION SUCCESSFUL"
echo "======================================"
echo
echo "OP VPS Optimizer is ready."
echo
echo "Commands:"
echo "  op-vps-optimizer status"
echo "  op-vps-optimizer apply"
echo "  op-vps-optimizer rollback"
echo "  op-vps-optimizer install-badvpn"
echo
echo "No manual curl, wget, sudo or chmod required."
