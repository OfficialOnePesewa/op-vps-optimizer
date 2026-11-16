#!/usr/bin/env bash
# ⚡ scripts/optimize.sh - apply BBR + TCP/UDP tuning (v2.0.0)
# Author: OfficialOnePesewa · Telegram: @OfficialOnePesewa
# Does NOT touch ZIVPN, UDP Custom, BadVPN (7100/7200/7300), 3x-ui or Trojan.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/lib/detect.sh"

CONF_SRC="$ROOT_DIR/config/99-op-optimizer.conf"
SYSCTL_FILE="/etc/sysctl.d/99-op-optimizer.conf"
QDISC_BIN="/usr/local/sbin/op-optimizer-qdisc"
QDISC_UNIT="/etc/systemd/system/op-optimizer-qdisc.service"
BACKUP_ROOT="/var/backups/op-vps-optimizer"
BK="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

[ "$(id -u)" -eq 0 ] || { echo "❌ Run as root (sudo)."; exit 1; }
[ -f "$CONF_SRC" ] || { echo "❌ Missing $CONF_SRC"; exit 1; }

op_banner
echo
echo "📋 Detected system:"
op_show_system
echo

echo "🔍 Checking kernel and BBR..."
modprobe tcp_bbr 2>/dev/null || true
AVAIL="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"
if ! echo " $AVAIL " | grep -q " bbr "; then
  echo "❌ BBR is not available in kernel $KERNEL."
  echo "   Install a kernel with BBR (XanMod gives BBRv3) and run again."
  exit 1
fi
case "$KERNEL" in
  *xanmod*) echo "🚀 XanMod kernel detected: BBRv3 build." ;;
  *)        echo "ℹ️  Stock kernel: using BBR (usually BBRv1). BBRv3 needs a kernel that ships it." ;;
esac

echo "💾 Backing up current settings to $BK ..."
mkdir -p "$BK"
sysctl -a 2>/dev/null | grep -E '^(net\.|fs\.file-max)' > "$BK/sysctl-before.txt"
[ -f "$SYSCTL_FILE" ] && cp -a "$SYSCTL_FILE" "$BK/"
cp -a /etc/sysctl.conf "$BK/" 2>/dev/null
ln -sfn "$BK" "$BACKUP_ROOT/latest"

echo "⚡ Applying tuning..."
install -m 644 "$CONF_SRC" "$SYSCTL_FILE"
if sysctl -p "$SYSCTL_FILE" > "$BK/sysctl-apply.log" 2>&1; then
  echo "   ✅ Kernel settings applied"
else
  echo "   ⚠️  Some keys are not supported by this kernel and were skipped."
  echo "      Details: $BK/sysctl-apply.log"
fi

echo "🌐 Setting fq queue on the default interface..."
cat > "$QDISC_BIN" <<'EOF'
#!/bin/sh
IF=$(ip -o route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -n "$IF" ] && tc qdisc replace dev "$IF" root fq 2>/dev/null
exit 0
EOF
chmod +x "$QDISC_BIN"
"$QDISC_BIN"

echo "🔁 Making the fq queue persist across reboots..."
cat > "$QDISC_UNIT" <<'EOF'
[Unit]
Description=OP VPS Optimizer: fq queue on default interface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/op-optimizer-qdisc
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now op-optimizer-qdisc.service >/dev/null 2>&1

echo
echo "🎉 Optimization applied."
echo "   🚦 Congestion control : $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "   📦 Default qdisc      : $(sysctl -n net.core.default_qdisc)"
exit 0
