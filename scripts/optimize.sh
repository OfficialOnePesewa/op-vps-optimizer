#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Run this command as root or with sudo."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "Error: Cannot identify the operating system."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "Error: Only Debian and Ubuntu are supported."
        exit 1
        ;;
esac

for cmd in sysctl mkdir cp date; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command not found: $cmd"
        exit 1
    fi
done

mkdir -p "$BACKUP_DIR"

# Back up the existing optimizer configuration before replacing it.
if [[ -f "$CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/99-op-vps-optimizer.conf.$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG" "$BACKUP_FILE"
    echo "Previous configuration backed up:"
    echo "$BACKUP_FILE"
fi

# Detect BBR support.
BBR_SUPPORTED=0
AVAILABLE_CC="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"

if grep -qw "bbr" <<< "$AVAILABLE_CC"; then
    BBR_SUPPORTED=1
fi

# Detect FQ support.
FQ_SUPPORTED=0

if command -v modprobe >/dev/null 2>&1; then
    if modprobe sch_fq 2>/dev/null; then
        FQ_SUPPORTED=1
    fi
fi

if [[ -d /sys/module/sch_fq ]]; then
    FQ_SUPPORTED=1
fi

# Build the optimizer configuration.
TMP_CONFIG="$(mktemp)"

cleanup() {
    rm -f "$TMP_CONFIG"
}
trap cleanup EXIT

{
    echo "# OP VPS Optimizer"
    echo "# Managed configuration - generated automatically."
    echo

    echo "# TCP buffer limits"
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
        echo "# BBR congestion control"
        echo "net.ipv4.tcp_congestion_control = bbr"
    fi

    if [[ "$FQ_SUPPORTED" -eq 1 ]]; then
        echo
        echo "# Fair Queue packet scheduling"
        echo "net.core.default_qdisc = fq"
    fi
} > "$TMP_CONFIG"

chmod 0644 "$TMP_CONFIG"
install -m 0644 "$TMP_CONFIG" "$CONFIG"

echo
echo "Applying OP VPS Optimizer settings..."

if ! sysctl -p "$CONFIG"; then
    echo
    echo "Warning: One or more settings could not be applied."
    echo "Check whether your VPS provider permits kernel network tuning."
    exit 1
fi

echo
echo "======================================"
echo "       OP VPS OPTIMIZER COMPLETE"
echo "======================================"
echo "Operating system: ${PRETTY_NAME:-Unknown}"
echo "BBR supported:    $([[ "$BBR_SUPPORTED" -eq 1 ]] && echo Yes || echo No)"
echo "FQ supported:     $([[ "$FQ_SUPPORTED" -eq 1 ]] && echo Yes || echo No)"
echo "Configuration:    $CONFIG"
echo
echo "Check settings with:"
echo "  sudo op-vps-optimizer status"
echo
echo "Rollback with:"
echo "  sudo op-vps-optimizer rollback"
echo "======================================"
