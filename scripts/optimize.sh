
#!/usr/bin/env bash
# OP-VPS Optimizer | OfficialOnePesewa
set -Eeuo pipefail

BASE="/opt/op-vps-optimizer"
CONF="/etc/sysctl.d/99-op-vps-optimizer.conf"
SOURCE="$BASE/config/99-op-vps-optimizer.conf"
BACKUPS="$BASE/backups"

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
[[ -s "$SOURCE" ]] || { echo "Missing config: $SOURCE"; exit 1; }

mkdir -p "$BACKUPS"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Preserve the previous project file or record that none existed.
if [[ -f "$CONF" ]]; then
  cp -a "$CONF" "$BACKUPS/config-before-$STAMP.conf"
else
  touch "$BACKUPS/no-previous-config"
fi

# Snapshot current TCP selection for reporting.
AVAILABLE="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
CURRENT="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if grep -qw bbr <<< "$AVAILABLE"; then
  cat > "$TMP" <<'EOF'
# OP-VPS Optimizer - supported TCP settings
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  echo "[OPVPS] BBR available; enabling it for TCP."
else
  : > "$TMP"
  echo "[OPVPS] BBR unavailable; keeping current algorithm: ${CURRENT:-unknown}"
fi

cat "$SOURCE" >> "$TMP"
install -o root -g root -m 0644 "$TMP" "$CONF"

if sysctl --system; then
  echo
  echo "[OPVPS] Network settings applied."
  echo "[OPVPS] No reboot requested."
  echo "[OPVPS] Run: opvps diagnose"
else
  echo "[OPVPS] One or more sysctl settings failed."
  echo "Inspect the errors and run: opvps rollback"
  exit 1
fi
