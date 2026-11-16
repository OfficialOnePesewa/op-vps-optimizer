#!/usr/bin/env bash
# 📊 scripts/status.sh - health check (v2.0.0)
# Author: OfficialOnePesewa · Telegram: @OfficialOnePesewa
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/lib/detect.sh"

op_banner
echo
op_show_system
echo
echo "📊 Tuning status"
echo "🚦 Congestion    : $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
echo "📦 Default qdisc : $(sysctl -n net.core.default_qdisc 2>/dev/null)"
echo "📥 TCP rmem max  : $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')"
echo "📤 TCP wmem max  : $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')"

IF=$(ip -o route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
echo "🌐 Interface     : ${IF:-unknown}"
echo "🔀 Qdisc on iface: $(tc qdisc show dev "$IF" root 2>/dev/null | awk '{print $2}')"

echo
echo "🔌 Protected ports:"
for p in 7100 7200 7300 443; do
  if ss -lntu 2>/dev/null | grep -q ":$p "; then
    echo "   ✅ $p listening"
  else
    echo "   ⚠️  $p not listening"
  fi
done
echo
echo "👤 $OP_AUTHOR · $OP_TELEGRAM"
