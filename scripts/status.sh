#!/usr/bin/env bash
set -u

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"

show_value() {
    local key="$1"
    local value

    value="$(sysctl -n "$key" 2>/dev/null || true)"

    if [[ -n "$value" ]]; then
        printf '%-48s %s\n' "$key" "$value"
    else
        printf '%-48s %s\n' "$key" "Not available"
    fi
}

echo "======================================"
echo "        OP VPS OPTIMIZER STATUS"
echo "======================================"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Operating system: ${PRETTY_NAME:-Unknown}"
fi

echo
echo "Configuration file:"
if [[ -f "$CONFIG" ]]; then
    echo "Installed: $CONFIG"
else
    echo "Not installed."
fi

echo
echo "TCP and network settings:"
show_value net.ipv4.tcp_congestion_control
show_value net.ipv4.tcp_available_congestion_control
show_value net.core.default_qdisc
show_value net.core.rmem_max
show_value net.core.wmem_max
show_value net.ipv4.tcp_rmem
show_value net.ipv4.tcp_wmem
show_value net.core.netdev_max_backlog
show_value net.core.somaxconn
show_value net.ipv4.tcp_max_syn_backlog
show_value net.ipv4.tcp_mtu_probing

echo
echo "Connection summary:"
if command -v ss >/dev/null 2>&1; then
    ss -s
else
    echo "The ss command is unavailable."
fi

echo
echo "Network interfaces:"
if command -v ip >/dev/null 2>&1; then
    ip -brief link
else
    echo "The ip command is unavailable."
fi

echo
echo "======================================"
