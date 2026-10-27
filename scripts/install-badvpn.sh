
#!/usr/bin/env bash
# OP-VPS Optimizer | OfficialOnePesewa
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates git cmake build-essential

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[OPVPS] Fetching upstream BadVPN source..."
git clone --depth 1 https://github.com/ambrop72/badvpn.git \
  "$WORK/badvpn"

cmake -S "$WORK/badvpn" -B "$WORK/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DBUILD_NOTHING_BY_DEFAULT=1 \
  -DBUILD_UDPGW=1

cmake --build "$WORK/build" --parallel 2

BIN="$(find "$WORK/build" -type f -name badvpn-udpgw -perm /111 -print -quit)"
if [[ -z "$BIN" ]]; then
  echo "ERROR: badvpn-udpgw was not found in build output."
  echo "Review the upstream build log; nothing has been started."
  exit 1
fi

# Verify the expected command-line options before installation.
"$BIN" --help > "$WORK/udpgw-help.txt" 2>&1 || true
if ! grep -q -- '--listen-addr' "$WORK/udpgw-help.txt"; then
  echo "ERROR: built binary does not advertise --listen-addr."
  exit 1
fi

install -o root -g root -m 0755 "$BIN" /usr/local/bin/badvpn-udpgw

if ! getent passwd badvpn >/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin badvpn
fi

SERVICE="/etc/systemd/system/badvpn-udpgw.service"
if [[ -f "$SERVICE" ]]; then
  cp -a "$SERVICE" "$SERVICE.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat > "$SERVICE" <<'UNIT'
[Unit]
Description=BadVPN UDP Gateway - OfficialOnePesewa
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=badvpn
Group=badvpn
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 256 --max-connections-for-client 10
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now badvpn-udpgw

echo
systemctl --no-pager --full status badvpn-udpgw || true
echo "Gateway: 127.0.0.1:7300"
echo "Logs: journalctl -u badvpn-udpgw -n 50 --no-pager"
