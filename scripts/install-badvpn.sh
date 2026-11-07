#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="/usr/local/src/badvpn"
INSTALL_BINARY="/usr/local/bin/badvpn-udpgw"
SERVICE_FILE="/etc/systemd/system/op-badvpn-udpgw.service"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this command as root or with sudo."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify operating system."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "BadVPN installer supports Debian and Ubuntu."
        exit 1
        ;;
esac

echo "WARNING: BadVPN upstream is archived and unmaintained."
echo "Review the source before installing."
echo

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    git \
    cmake \
    build-essential \
    pkg-config \
    libssl-dev

mkdir -p /usr/local/src
rm -rf "$SOURCE_DIR"

echo "Downloading BadVPN source..."
git clone --depth 1 https://github.com/ambrop72/badvpn.git "$SOURCE_DIR"

mkdir -p "$SOURCE_DIR/build"
cd "$SOURCE_DIR/build"

echo "Configuring BadVPN build..."
cmake .. \
    -DBUILD_NOTHING_BY_DEFAULT=1 \
    -DBUILD_UDPGW=1

echo "Compiling BadVPN-UDPGW..."
cmake --build . --parallel "$(nproc)"

BUILT_BINARY="$(find "$SOURCE_DIR/build" -type f -name badvpn-udpgw -perm /111 -print -quit)"

if [[ -z "$BUILT_BINARY" ]]; then
    echo "Build completed, but badvpn-udpgw binary was not found."
    echo "Check the upstream build output before continuing."
    exit 1
fi

install -m 0755 "$BUILT_BINARY" "$INSTALL_BINARY"

if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "The systemd service file is missing:"
    echo "$SERVICE_FILE"
    exit 1
fi

mkdir -p /etc/op-badvpn

if [[ ! -f /etc/op-badvpn/udpgw.env ]]; then
    cat > /etc/op-badvpn/udpgw.env <<'EOF'
LISTEN_ADDR=127.0.0.1:7300
MAX_CLIENTS=256
EOF
    chmod 0600 /etc/op-badvpn/udpgw.env
fi

systemctl daemon-reload
systemctl enable --now op-badvpn-udpgw.service

echo
echo "BadVPN-UDPGW installation completed."
echo "Default listening address: 127.0.0.1:7300"
echo
echo "Check service status with:"
echo "  sudo systemctl status op-badvpn-udpgw"
