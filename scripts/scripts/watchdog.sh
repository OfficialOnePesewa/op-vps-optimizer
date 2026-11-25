#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: watchdog
# Runs every minute. Restarts udpgw if its ports are down and
# reapplies the tuning if the kernel values have been reset.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

UDPGW_UNIT="op-badvpn-udpgw.service"
LOG="/var/log/op-watchdog.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# Keep the log small
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then
  tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# 1. Restart udpgw if any protected port is down
down=0
for p in $OP_PROTECTED_PORTS; do
  [ "$(port_state "$p")" = "down" ] && down=1
done

if [ "$down" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl cat "$UDPGW_UNIT" >/dev/null 2>&1; then
    systemctl restart "$UDPGW_UNIT" 2>/dev/null
    log "udpgw port down, restarted $UDPGW_UNIT"
  fi
fi

# 2. Reapply tuning if the optimizer file exists but the kernel values drifted
if [ -f "$OP_SYSCTL_FILE" ]; then
  want="$(awk -F' = ' '/tcp_congestion_control/ {print $2}' "$OP_SYSCTL_FILE")"
  have="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    sysctl -p "$OP_SYSCTL_FILE" >/dev/null 2>&1
    log "tuning drifted (cc $have -> $want), reapplied"
  fi
fi
