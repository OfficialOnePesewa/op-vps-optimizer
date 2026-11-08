#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="/usr/local/src/badvpn"
INSTALL_BINARY="/usr/local/bin/badvpn-udpgw"
TEMPLATE_UNIT="/etc/systemd/system/op-badvpn-udpgw@.service"
LEGACY_UNIT="op-badvpn-udpgw.service"
ENV_DIR="/etc/op-badvpn"
ENV_FILE="$ENV_DIR/udpgw.env"
BADVPN_REPO="https://github.com/ambrop72/badvpn.git"
BADVPN_TAG="1.999.130"
SERVICE_USER="opudpgw"
PORTS=(7100 7200 7300)

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
    debian|ubuntu) ;;
    *) echo "BadVPN installer supports Debian and Ubuntu."; exit 1 ;;
esac

echo "NOTE: BadVPN upstream is archived and unmaintained."
echo

export DEBIAN_FRONTEND=noninteractive

apt-get update || echo "WARN: apt update failed, continuing..."
apt-get install -y git cmake build-essential pkg-config libssl-dev iproute2

mkdir -p /usr/local/src
rm -rf "$SOURCE_DIR"

echo "Downloading BadVPN source (tag $BADVPN_TAG)..."
if ! git clone --depth 1 --branch "$BADVPN_TAG" "$BADVPN_REPO" "$SOURCE_DIR" 2>/dev/null; then
    echo "WARN: tag $BADVPN_TAG not found, using default branch."
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 "$BADVPN_REPO" "$SOURCE_DIR"
fi

mkdir -p "$SOURCE_DIR/build"
cd "$SOURCE_DIR/build"

echo "Configuring BadVPN build..."
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1

echo "Compiling BadVPN-UDPGW..."
cmake --build . --parallel "$(nproc)"

BUILT_BINARY="$(find "$SOURCE_DIR/build" -type f -name badvpn-udpgw -perm /111 -print -quit)"
if [[ -z "$BUILT_BINARY" ]]; then
    echo "Build completed, but badvpn-udpgw binary was not found."
    exit 1
fi

install -m 0755 "$BUILT_BINARY" "$INSTALL_BINARY"

# Dedicated unprivileged user.
id "$SERVICE_USER" >/dev/null 2>&1 || \
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"

# Config: migrate old low-limit config (backup kept).
mkdir -p "$ENV_DIR"
if [[ ! -f "$ENV_FILE" ]] || ! grep -q '^MAX_CONN_PER_CLIENT=' "$ENV_FILE"; then
    [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$ENV_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cat > "$ENV_FILE" <<'EOF'
MAX_CLIENTS=1000
MAX_CONN_PER_CLIENT=64
EOF
    chmod 0600 "$ENV_FILE"
fi

# Template service: one instance per port.
cat > "$TEMPLATE_UNIT" <<'EOF'
[Unit]
Description=OP BadVPN UDPGW on 127.0.0.1:%i
After=network.target

[Service]
Type=simple
User=opudpgw
Group=opudpgw
EnvironmentFile=/etc/op-badvpn/udpgw.env
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:%i --max-clients ${MAX_CLIENTS} --max-connections-for-client ${MAX_CONN_PER_CLIENT} --loglevel warning
Restart=always
RestartSec=2
LimitNOFILE=65535
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Retire the old single-port service made by the previous installer version.
if systemctl list-unit-files "$LEGACY_UNIT" >/dev/null 2>&1; then
    systemctl disable --now "$LEGACY_UNIT" >/dev/null 2>&1 || true
fi

port_busy() {
    ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
}

STARTED=()
SKIPPED=()

for p in "${PORTS[@]}"; do
    unit="op-badvpn-udpgw@${p}.service"
    if systemctl is-active --quiet "$unit"; then
        systemctl restart "$unit"
        STARTED+=("$p")
    elif port_busy "$p"; then
        echo "Port $p already in use by another service - left untouched."
        SKIPPED+=("$p")
    else
        systemctl enable --now "$unit"
        STARTED+=("$p")
    fi
done

sleep 1

echo
echo "BadVPN-UDPGW installation completed."
echo "Managed ports:  ${STARTED[*]:-none}"
echo "Skipped (busy): ${SKIPPED[*]:-none}"
echo "Limits:         $(tr '\n' ' ' < "$ENV_FILE")"
echo
echo "Listening:"
ss -ltnH | grep -E ':(7100|7200|7300)\b' || echo "  nothing listening yet"
echo
echo "Customers keep using 127.0.0.1:7300 as UDPGW."
echo "Status: sudo systemctl status 'op-badvpn-udpgw@*'"
