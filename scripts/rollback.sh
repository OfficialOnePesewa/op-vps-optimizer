#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: rollback
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

UDPGW_DROPIN_DIR="/etc/systemd/system/op-badvpn-udpgw.service.d"

require_root

# Remove the optimizer's files
rm -f "$OP_SYSCTL_FILE" "$OP_LIMITS_FILE"
restore_originals

# Remove the MSS clamp rule (repeat in case it was added more than once)
if command -v iptables >/dev/null 2>&1; then
  while iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN \
      -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || break
  done
fi

# Remove the Alpine boot-time block
if [ -f /etc/sysctl.conf ]; then
  sed -i '/# BEGIN op-vps-optimizer/,/# END op-vps-optimizer/d' /etc/sysctl.conf
fi

# Remove the watchdog timer and the udpgw auto-restart setting
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now op-watchdog.timer >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/op-watchdog.service /etc/systemd/system/op-watchdog.timer
  rm -f "$UDPGW_DROPIN_DIR/op-restart.conf"
  rmdir "$UDPGW_DROPIN_DIR" 2>/dev/null || true
  systemctl daemon-reload
fi

echo "[+] Rolled back. Reconnect any sessions that feel slow. A reboot restores every default."
