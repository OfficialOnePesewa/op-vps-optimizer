#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: deep tuning
# Removes CPU and network bottlenecks that cap UDP tunnel throughput.
# Safe on most VPS. Anything the host does not allow is skipped and reported.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

DEEPTUNE_UNIT="/etc/systemd/system/op-deeptune.service"

require_root
detect_os

echo "== OP Deep Tune =="

NCPU="$(nproc 2>/dev/null || echo 1)"
[ "$NCPU" -gt 62 ] && NCPU=62
echo "[*] CPU cores: $NCPU"

# 1. CPU governor: keep cores at full speed instead of scaling down
gov_set=0
for g in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  [ -w "$g" ] || continue
  if echo performance > "$g" 2>/dev/null; then gov_set=1; fi
done
if [ "$gov_set" -eq 1 ]; then
  echo "[*] CPU governor set to performance"
else
  echo "[-] CPU governor is not controllable here (normal on most VPS)"
fi

DEV="$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [ -z "$DEV" ]; then
  echo "[!] No default network interface found. Network tuning skipped."
  exit 0
fi
echo "[*] Network interface: $DEV"

# 2. NIC offloads: let the network card handle segmentation work
if ! command -v ethtool >/dev/null 2>&1; then
  pkg_install ethtool >/dev/null 2>&1 || true
fi
if command -v ethtool >/dev/null 2>&1; then
  for feat in gro gso tso; do
    if ethtool -K "$DEV" "$feat" on >/dev/null 2>&1; then
      echo "    $feat: on"
    else
      echo "    $feat: not changeable on this NIC"
    fi
  done
else
  echo "[-] ethtool not available, offload tuning skipped"
fi

# 3. Spread packet processing across all cores (RPS/RFS on receive, XPS on transmit)
if [ "$NCPU" -ge 2 ]; then
  MASK="$(printf '%x' $(( (1 << NCPU) - 1 )))"
  for q in /sys/class/net/"$DEV"/queues/rx-*; do
    [ -e "$q/rps_cpus" ] && echo "$MASK" > "$q/rps_cpus" 2>/dev/null
    [ -e "$q/rps_flow_cnt" ] && echo 4096 > "$q/rps_flow_cnt" 2>/dev/null
  done
  echo 32768 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null
  for q in /sys/class/net/"$DEV"/queues/tx-*; do
    [ -e "$q/xps_cpus" ] && echo "$MASK" > "$q/xps_cpus" 2>/dev/null
  done
  echo "[*] Packet processing spread across $NCPU cores"
else
  echo "[-] Single core: RPS/XPS not needed"
fi

# 4. Make these settings survive reboot
if command -v systemctl >/dev/null 2>&1; then
  cat > "$DEEPTUNE_UNIT" <<EOF
[Unit]
Description=OP VPS Optimizer deep tuning (CPU governor, offloads, RPS/XPS)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HERE/deeptune.sh

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable op-deeptune.service >/dev/null 2>&1 \
    && echo "[*] Deep tuning will re-apply on every boot" \
    || echo "[!] Could not enable boot service"
fi

echo "[+] Deep tune complete. Run op-bench to measure."
