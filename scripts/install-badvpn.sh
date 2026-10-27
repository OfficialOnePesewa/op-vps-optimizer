
#!/usr/bin/env bash
# ============================================================
# OfficialOnePesewa OP-VPS Optimizer
# BadVPN UDPGW Installer for Ubuntu / Debian
# CMake compatibility fix + systemd service
# ============================================================

set -Eeuo pipefail
umask 022

SERVICE_NAME="badvpn-udpgw"
INSTALL_PATH="/usr/local/bin/badvpn-udpgw"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LISTEN_ADDR="127.0.0.1:7300"
MAX_CLIENTS="256"
MAX_CONNECTIONS="10"

WORKDIR=""
SUCCESS=0

cleanup() {
    local status=$?
    if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then
        if [[ "$status" -eq 0 && "$SUCCESS" -eq 1 ]]; then
            rm -rf "$WORKDIR"
        else
            echo
            echo "Build files retained for troubleshooting: $WORKDIR"
        fi
    fi
}
trap cleanup EXIT

log() {
    printf '\n[%s] %s\n' "OPUDP" "$*"
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] || fail "Run this installer as root, for example: sudo bash install-badvpn.sh"

[[ -r /etc/os-release ]] || fail "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    ubuntu|debian) ;;
    *) fail "Supported systems: Ubuntu and Debian. Detected: ${PRETTY_NAME:-unknown}" ;;
esac

command -v apt-get >/dev/null 2>&1 ||
    fail "apt-get is unavailable on this system."

log "Updating package lists and installing build dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    ca-certificates \
    git \
    cmake \
    build-essential

log "Checking available disk space..."
AVAILABLE_KB=$(df -Pk /tmp | awk 'NR==2 {print $4}')
[[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]] ||
    fail "Could not determine available disk space."
(( AVAILABLE_KB >= 200000 )) ||
    fail "At least 200 MB of free space in /tmp is recommended."

log "Preparing temporary build directory..."
WORKDIR=$(mktemp -d /tmp/op-badvpn-build.XXXXXX)
SOURCE_DIR="$WORKDIR/source"
BUILD_DIR="$WORKDIR/build"

log "Downloading BadVPN source..."
git clone --depth 1 \
    https://github.com/ambrop72/badvpn.git \
    "$SOURCE_DIR"

[[ -f "$SOURCE_DIR/CMakeLists.txt" ]] ||
    fail "BadVPN source is missing CMakeLists.txt."

log "Configuring BadVPN with the CMake compatibility fix..."
cmake \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_NOTHING_BY_DEFAULT=1 \
    -DBUILD_UDPGW=1

log "Compiling BadVPN UDPGW..."
JOBS=$(nproc 2>/dev/null || echo 1)
(( JOBS > 4 )) && JOBS=4
cmake --build "$BUILD_DIR" --parallel "$JOBS"

log "Locating the compiled UDPGW executable..."
BINARY=""

while IFS= read -r candidate; do
    if [[ -f "$candidate" && -x "$candidate" ]]; then
        BINARY="$candidate"
        break
    fi
done < <(find "$BUILD_DIR" -type f -name badvpn-udpgw -print)

[[ -n "$BINARY" ]] ||
    fail "badvpn-udpgw was not produced. Check the retained build directory."

log "Checking executable..."
"$BINARY" --help >"$WORKDIR/udpgw-help.txt" 2>&1 ||
    true

if ! grep -q -- '--listen-addr' "$WORKDIR/udpgw-help.txt"; then
    cat "$WORKDIR/udpgw-help.txt"
    fail "The compiled binary does not advertise --listen-addr; refusing to install an incompatible build."
fi

log "Installing executable..."
install -o root -g root -m 0755 "$BINARY" "$INSTALL_PATH"

log "Creating dedicated service account..."
if ! id badvpn >/dev/null 2>&1; then
    useradd --system --no-create-home \
        --shell /usr/sbin/nologin badvpn
fi

log "Writing systemd service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OfficialOnePesewa BadVPN UDP Gateway
Documentation=https://github.com/ambrop72/badvpn
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=badvpn
Group=badvpn
ExecStart=${INSTALL_PATH} --listen-addr ${LISTEN_ADDR} --max-clients ${MAX_CLIENTS} --max-connections-for-client ${MAX_CONNECTIONS}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF

log "Enabling and starting service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 2

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    journalctl -u "$SERVICE_NAME" -n 60 --no-pager || true
    fail "BadVPN UDPGW service did not start. Review the logs above."
fi

SUCCESS=1

log "Installation completed successfully."
echo
echo "Binary:        $INSTALL_PATH"
echo "Service:       $SERVICE_NAME"
echo "Listen address: $LISTEN_ADDR"
echo "Max clients:   $MAX_CLIENTS"
echo "Connections/client: $MAX_CONNECTIONS"
echo
echo "Useful commands:"
echo "  systemctl status $SERVICE_NAME"
echo "  journalctl -u $SERVICE_NAME -n 50 --no-pager"
echo "  systemctl restart $SERVICE_NAME"
echo "  ss -lunp | grep 7300"
echo
echo "Security note: UDPGW listens on loopback only (127.0.0.1)."
echo "A compatible local tunnel/client must connect to this address."
