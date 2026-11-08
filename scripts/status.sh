#!/usr/bin/env bash
set -u

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
ORIG="/var/backups/op-vps-optimizer/sysctl-original.conf"

show_value() {
    local key="$1" value
    value="$(sysctl -n "$key" 2>/dev/null || true)"
    printf '%-48s %s\n' "$key" "${value:-Not available}"
}

check() {
    # check "label" "PASS|FAIL|WARN" "detail"
    printf '  [%s] %-26s %s\n' "$2" "$1" "$3"
}

echo "======================================"
echo "        OP VPS OPTIMIZER STATUS"
echo "======================================"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Operating system: ${PRETTY_NAME:-Unknown}"
fi
echo "Kernel:           $(uname -r)"
echo "CPU cores:        $(nproc 2>/dev/null || echo '?')"
echo "Load average:     $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

echo
echo "Configuration file:"
if [[ -f "$CONFIG" ]]; then
    echo "Installed: $CONFIG"
else
    echo "Not installed."
fi
[[ -f "$ORIG" ]] && echo "Original values saved: yes (rollback ready)" \
                 || echo "Original values saved: no"

echo
echo "TCP and network settings:"
show_value net.ipv4.tcp_congestion_control
show_value net.ipv4.tcp_available_congestion_control
show_value net.core.default_qdisc
show_value net.core.rmem_max
show_value net.core.wmem_max
show_value net.ipv4.tcp_rmem
show_value net.ipv4.tcp_wmem
show_value net.ipv4.udp_rmem_min
show_value net.core.netdev_max_backlog
show_value net.core.somaxconn
show_value net.ipv4.tcp_max_syn_backlog
show_value net.ipv4.tcp_notsent_lowat
show_value net.ipv4.tcp_slow_start_after_idle
show_value net.ipv4.tcp_mtu_probing
show_value net.ipv4.tcp_fastopen

if [[ -e /proc/sys/net/netfilter/nf_conntrack_max ]]; then
    echo
    echo "Connection tracking:"
    show_value net.netfilter.nf_conntrack_count
    show_value net.netfilter.nf_conntrack_max
    show_value net.netfilter.nf_conntrack_udp_timeout_stream
fi

echo
echo "Streaming health check:"

cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
[[ "$cc" == "bbr" ]] && check "BBR congestion control" PASS "$cc" \
                     || check "BBR congestion control" FAIL "${cc:-unknown}"

qd="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
[[ "$qd" == "fq" ]] && check "FQ scheduler" PASS "$qd" \
                    || check "FQ scheduler" FAIL "${qd:-unknown}"

rmax="$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)"
if [[ "$rmax" -ge 67108864 ]]; then
    check "Large TCP buffers" PASS "${rmax} bytes"
else
    check "Large TCP buffers" FAIL "${rmax} bytes (need 67108864)"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet op-stream-boost.service; then
        check "Interface boost service" PASS "active"
    else
        check "Interface boost service" FAIL "not active"
    fi
fi

if command -v iptables >/dev/null 2>&1 && \
   iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
    check "MSS clamp rule" PASS "present"
else
    check "MSS clamp rule" WARN "not found"
fi

IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')"
if [[ -n "${IFACE:-}" ]]; then
    txq="$(cat "/sys/class/net/$IFACE/tx_queue_len" 2>/dev/null || echo '?')"
    nq="$(tc qdisc show dev "$IFACE" 2>/dev/null | head -n1 | awk '{print $2}')"
    echo "  Interface: $IFACE  txqueuelen: $txq  qdisc: ${nq:-unknown}"
fi

cores="$(nproc 2>/dev/null || echo 1)"
load1="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo 0)"
if awk -v l="$load1" -v c="$cores" 'BEGIN{exit !(l > c)}'; then
    check "CPU load" WARN "load $lo
