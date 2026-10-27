
#!/usr/bin/env bash
# OP-VPS Optimizer | OfficialOnePesewa
set -u

echo "=== OP-VPS VOIP & GAMING DIAGNOSTICS ==="
date -Is
echo

echo "=== OS / CPU / MEMORY ==="
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release || true
uname -r
nproc
free -h
uptime

echo
echo "=== TCP CONGESTION CONTROL ==="
sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null || true
sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
sysctl net.core.default_qdisc 2>/dev/null || true

echo
echo "=== UDP BUFFER LIMITS ==="
sysctl net.core.rmem_max net.core.wmem_max 2>/dev/null || true
sysctl net.ipv4.ip_forward 2>/dev/null || true

echo
echo "=== NETWORK INTERFACES ==="
ip -br address
ip route
ip -s link

echo
echo "=== SOCKET SUMMARY ==="
ss -s 2>/dev/null || true
ss -lunp 2>/dev/null || true
ss -ltnp 2>/dev/null || true

echo
echo "=== UDP STATISTICS ==="
grep -E '^(Udp:|Ip:)' /proc/net/snmp || true
cat /proc/net/softnet_stat 2>/dev/null || true

echo
echo "=== BADVPN UDPGW ==="
if command -v badvpn-udpgw >/dev/null 2>&1; then
  badvpn-udpgw --version 2>&1 || true
else
  echo "Binary not found."
fi
systemctl --no-pager --full status badvpn-udpgw 2>/dev/null || true

echo
echo "=== RECENT UDPGW LOGS ==="
journalctl -u badvpn-udpgw -n 20 --no-pager 2>/dev/null || true

echo
echo "=== NETWORK DROP / ERROR COUNTERS ==="
nstat -az 2>/dev/null |
  grep -Ei 'Udp(InErrors|RcvbufErrors|SndbufErrors)|Ip(InDiscards|InHdrErrors)' || true

echo
echo "=== RECENT KERNEL WARNINGS ==="
journalctl -k -p warning -n 15 --no-pager 2>/dev/null || true

echo
echo "=== OP-VPS CONFIGURATION ==="
if [[ -f /etc/sysctl.d/99-op-vps-optimizer.conf ]]; then
  cat /etc/sysctl.d/99-op-vps-optimizer.conf
else
  echo "Not installed."
fi

echo
echo "Diagnostics complete."
echo "Check packet counters before and after a controlled test."
