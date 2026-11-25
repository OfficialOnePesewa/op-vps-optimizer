#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: apply tuning
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

UDPGW_UNIT="op-badvpn-udpgw.service"
UDPGW_DROPIN_DIR="/etc/systemd/system/$UDPGW_UNIT.d"
WATCHDOG_SVC="/etc/systemd/system/op-watchdog.service"
WATCHDOG_TIMER="/etc/systemd/system/op-watchdog.timer"

require_root
detect_os
ensure_deps
echo "[*] Detected: $OS_PRETTY (package manager: $PKG)"
check_virt
save_originals

modprobe tcp_bbr 2>/dev/null || true
modprobe nf_conntrack 2>/dev/null || true
if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
  CC="bbr"
  QDISC="fq"
else
  CC="cubic"
  QDISC="fq_codel"
  echo "[!] BBR is not available on this kernel (needs 4.9 or newer). Using cubic."
fi

# Size buffers and the connection table by RAM. These are caps, not fixed allocations.
RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 1024)"
if [ "$RAM_MB" -ge 3800 ]; then
  BUF_MAX=67108864
  BACKLOG=250000
elif [ "$RAM_MB" -ge 1800 ]; then
  BUF_MAX=33554432
  BACKLOG=125000
else
  BUF_MAX=16777216
  BACKLOG=50000
fi

CT_MAX=$((RAM_MB * 256))
[ "$CT_MAX" -gt 1048576 ] && CT_MAX=1048576
[ "$CT_MAX" -lt 65536 ] && CT_MAX=65536
echo "[*] RAM: ${RAM_MB} MB, buffer cap: $((BUF_MAX / 1048576)) MB, conntrack: $CT_MAX"

echo "[*] Writing $OP_SYSCTL_FILE"
cat > "$OP_SYSCTL_FILE" <<EOF
# OP VPS Optimizer - Streaming Edition
# Remove with: op-rollback

# Congestion control and queueing
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# Socket buffers: high ceilings so fast downloads and uploads are not capped
net.core.rmem_max = $BUF_MAX
net.core.wmem_max = $BUF_MAX
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 131072 $BUF_MAX
net.ipv4.tcp_wmem = 4096 65536 $BUF_MAX
net.core.optmem_max = 65536

# UDP buffers (ZIVPN, UDP Custom, QUIC and udpgw traffic)
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000

# Fewer stalls during handshakes and on mobile links
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3

# Keep connections alive through carrier NAT and idle periods
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_udp_timeout = 120
net.netfilter.nf_conntrack_udp_timeout_stream = 300

# Connection capacity
net.core.somaxconn = 4096
net.core.netdev_max_backlog = $BACKLOG
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10240 65535
net.netfilter.nf_conntrack_max = $CT_MAX
fs.file-max = 1048576
EOF

echo "[*] Applying settings (no reboot needed)"
apply_sysctl_file "$OP_SYSCTL_FILE"

# Clamp TCP MSS through the tunnel so large packets don't get dropped
echo "[*] Applying TCP MSS clamp for tunnelled traffic"
if command -v iptables >/dev/null 2>&1; then
  if ! iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN \
       -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
      -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
      && echo "    MSS clamp added" \
      || echo "    MSS clamp could not be added (iptables error), skipped"
  else
    echo "    MSS clamp already present"
  fi
else
  echo "    iptables not found, MSS clamp skipped"
fi

# Alpine reads boot-time sysctl from /etc/sysctl.conf, so add a marked block there
if [ "$PKG" = "apk" ] && [ -f /etc/sysctl.conf ]; then
  sed -i '/# BEGIN op-vps-optimizer/,/# END op-vps-optimizer/d' /etc/sysctl.conf
  {
    echo "# BEGIN op-vps-optimizer"
    cat "$OP_SYSCTL_FILE"
    echo "# END op-vps-optimizer"
  } >> /etc/sysctl.conf
  echo "[*] Alpine: boot-time block added to /etc/sysctl.conf"
fi

echo "[*] Writing $OP_LIMITS_FILE"
mkdir -p /etc/security/limits.d
cat > "$OP_LIMITS_FILE" <<EOF
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

# Auto-restart the udpgw service if it crashes
if command -v systemctl >/dev/null 2>&1 && systemctl cat "$UDPGW_UNIT" >/dev/null 2>&1; then
  echo "[*] Setting auto-restart for $UDPGW_UNIT"
  mkdir -p "$UDPGW_DROPIN_DIR"
  cat > "$UDPGW_DROPIN_DIR/op-restart.conf" <<EOF
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=2
EOF
  systemctl daemon-reload
  systemctl restart "$UDPGW_UNIT" 2>/dev/null || true
fi

# Install the watchdog timer (systemd only)
if command -v systemctl >/dev/null 2>&1; then
  echo "[*] Installing watchdog timer (runs every 60 seconds)"
  cat > "$WATCHDOG_SVC" <<EOF
[Unit]
Description=OP VPS Optimizer watchdog

[Service]
Type=oneshot
ExecStart=$HERE/watchdog.sh
EOF
  cat > "$WATCHDOG_TIMER" <<EOF
[Unit]
Description=Run OP VPS Optimizer watchdog every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now op-watchdog.timer >/dev/null 2>&1 \
    && echo "    watchdog timer active" \
    || echo "    could not enable watchdog timer"
else
  echo "[!] No systemd found. Watchdog timer skipped. Run $HERE/watchdog.sh from cron if needed."
fi

echo "[*] Checking protected VPN services"
for p in $OP_PROTECTED_PORTS; do
  state="$(port_state "$p")"
  if [ "$state" = "up" ]; then
    echo "    port $p: up"
  else
    echo "    port $p: $state (if this was running before, check your udpgw service)"
  fi
done

echo "[+] Optimization applied. Run op-status to verify."
