#!/usr/bin/env bash
# ↩️ scripts/rollback.sh - undo OP VPS Optimizer changes (v2.0.0)
# Author: OfficialOnePesewa · Telegram: @OfficialOnePesewa
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/lib/detect.sh"

[ "$(id -u)" -eq 0 ] || { echo "❌ Run as root (sudo)."; exit 1; }

BACKUP_ROOT="/var/backups/op-vps-optimizer"
BK="$(readlink -f "$BACKUP_ROOT/latest" 2>/dev/null)"
SYSCTL_FILE="/etc/sysctl.d/99-op-optimizer.conf"
QDISC_BIN="/usr/local/sbin/op-optimizer-qdisc"
QDISC_UNIT="/etc/systemd/system/op-optimizer-qdisc.service"

op_banner
echo
echo "↩️  Rolling back OP VPS Optimizer..."

systemctl disable --now op-optimizer-qdisc.service >/dev/null 2>&1
rm -f "$QDISC_UNIT" "$QDISC_BIN" "$SYSCTL_FILE"
systemctl daemon-reload

if [ -n "$BK" ] && [ -f "$BK/sysctl-before.txt" ]; then
  echo "♻️  Restoring previous values from $BK ..."
  while IFS= read -r line; do
    sysctl -w "$(echo "$line" | sed 's/ *= */=/')" >/dev/null 2>&1
  done < "$BK/sysctl-before.txt"
else
  echo "⚠️  No backup found. Setting congestion control back to cubic."
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
fi

IF=$(ip -o route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -n "$IF" ] && tc qdisc replace dev "$IF" root fq_codel 2>/dev/null

echo "✅ Rollback complete. Network settings are back to their previous values."
echo "👤 $OP_AUTHOR · $OP_TELEGRAM"
