#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this command as root or with sudo."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify operating system."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "Unsupported operating system: ${ID:-unknown}"
        exit 1
        ;;
esac

if ! command -v sysctl >/dev/null 2>&1; then
    echo "sysctl is not installed."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

if [[ -f "$CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/99-op-vps-optimizer.conf.$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG" "$BACKUP_FILE"
    echo "Previous optimizer configuration backed up to:"
    echo "$BACKUP_FILE"
fi

BBR_SUPPORTED=0
FQ_SUPPORTED=0

AVAILABLE_CC="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

if grep -qw bbr <<< "$AVAILABLE_CC"; then
    BBR_SUPPORTED=1
fi

if command -v modprobe >/dev/null 2>&1; then
    modprobe sch_fq 2>/dev/null || true
fi

if [[ -d /sys/module/sch_fq ]] || \
   grep -qw fq /proc/net/psched 2>/dev/null; then
    FQ_SUPPORTED=1
fi

{
    echo "# OP VPS Optimizer"
    echo "# Managed file: do not edit unless you understand sysctl."
    echo
    echo "# TCP buffer auto-tuning limits"
    echo "net.core.rmem_max = 16777216"
    echo "net.core.wmem_max = 16777216"
    echo "net.ipv4.tcp_rmem = 4096 87380 16777216"
    echo "net.ipv4.tcp_wmem = 4096 65536 16777216"
    echo
    echo "# Network queue and connection backlogs"
    echo "net.core.netdev_max_backlog = 4096"
    echo "net.core.somaxconn = 4096"
    echo "net.ipv4.tcp_max_syn_backlog = 4096"
    echo
    echo "# TCP behavior"
    echo "net.ipv4.tcp_slow_start_after_idle = 0"
    echo "net.ipv4.tcp_mtu_probing = 1"

    if [[ "$BBR_SUPPORTED" -eq 1 ]]; then
        echo
        echo "# Enable BBR when supported by the running kernel"
        echo "net.ipv4.tcp_congestion_control = bbr"
    fi

    if [[ "$FQ_SUPPORTED" -eq 1 ]]; then
        echo "net.core.default_qdisc = fq"
    fi
} > "$CONFIG"

chmod 0644 "$CONFIG"

echo "Applying optimizer settings..."
sysctl -p "$CONFIG"

echo
echo "Optimization profile applied."
echo "BBR support: $([[ "$BBR_SUPPORTED" -eq 1 ]] && echo yes || echo no)"
echo "FQ support:  $([[ "$FQ_SUPPORTED" -eq 1 ]] && echo yes || echo no)"
echo
echo "Use 'sudo op-vps-optimizer status' to inspect the current settings."
