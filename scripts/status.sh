#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: status
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

UDPGW_UNIT="op-badvpn-udpgw.service"

detect_os

echo "== System =="
echo "OS:       $OS_PRETTY"
echo "Kernel:   $(uname -r)"
echo "Pkg mgr:  $PKG"
echo

echo "== TCP =="
echo "cc:       $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo n/a)"
echo "qdisc:    $(sysctl -n net.core.default_qdisc 2>/dev/null || echo n/a)"
echo "rmem_max: $(sysctl -n net.core.rmem_max 2>/dev/null || echo n/a)"
echo "wmem_max: $(sysctl -n net.core.wmem_max 2>/dev/null || echo n/a)"
echo

echo "== Optimizer =="
if [ -f "$OP_SYSCTL_FILE" ]; then
  echo "tuning file: installed"
else
  echo "tuning file: not installed"
fi
echo

echo "== Services =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl cat "$UDPGW_UNIT" >/dev/null 2>&1; then
    echo "udpgw:    $(systemctl is-active "$UDPGW_UNIT")"
  else
    echo "udpgw:    unit not found ($UDPGW_UNIT)"
  fi
  if [ -f /etc/systemd/system/op-watchdog.timer ]; then
    echo "watchdog: $(systemctl is-active op-watchdog.timer)"
  else
    echo "watchdog: not installed"
  fi
else
  echo "systemd not found, service checks skipped"
fi
echo

echo "== Protected VPN ports =="
for p in $OP_PROTECTED_PORTS; do
  echo "port $p: $(port_state "$p")"
done
