#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: rollback
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

require_root

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

if [ -f /etc/sysctl.conf ]; then
  sed -i '/# BEGIN op-vps-optimizer/,/# END op-vps-optimizer/d' /etc/sysctl.conf
fi

echo "[+] Rolled back. Reconnect any sessions that feel slow. A reboot restores every default."
