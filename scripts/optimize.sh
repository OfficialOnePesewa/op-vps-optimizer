#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"
BOOST_BIN="/usr/local/sbin/op-stream-boost"
BOOST_SERVICE="/etc/systemd/system/op-stream-boost.service"
MODULES_CONF="/etc/modules-load.d/op-vps-optimizer.conf"

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
    debian|ubuntu) ;;
    *) echo "Error: Only Debian and Ubuntu are supported."; exit 1 ;;
esac

for cmd in sysctl mkdir cp date install; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: Required command not found: $cmd"; exit 1; }
done

mkdir -p "$BACKUP_DIR"

KEYS=(
    net.core.default_qdisc
    net.ipv4.tcp_congestion_control
    net.core.rmem_max net.core.wmem_max
    net.core.rmem_default net.core.wmem_default
    net.ipv4.tcp_rmem net.ipv4.tcp_wmem
    net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min
    net.core.netdev_max_backlog net.core.somaxconn
    net.ipv4.tcp_max_syn_backlog
    net.ipv4.tcp_slow_start_after_idle
    net.ipv4.tcp_notsent_lowat
    net.ipv4.tcp_mtu_probing
    net.ipv4.tcp_fastopen
    net.ipv4.tcp_no_metrics_save
    net.ipv4.tcp_tw_reuse
    net.ipv4.tcp_fin_timeout
    net.netfilter.nf_conntrack_max
    net.netfilter.nf_conntrack_udp_timeout_stream
)

# Save original kernel values once (first run only) for rollback.
ORIG="$BACKUP_DIR/sysctl-original.conf"
if [[ ! -f "$ORIG" ]]; then
    : > "$ORIG"
    for k in "${KEYS[@]}"; do
        v="$(sysctl -n "$k" 2>/dev/null || true)"
        [[ -n "$v" ]] && echo "$k = $v" >> "$ORIG"
    done
    echo "Original values saved: $ORIG"
fi

# Back up the previous optimizer config.
if [[ -f "$CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/99-op-vps-optimizer.conf.$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG" "$BACKUP_FILE"
    echo "Previous configuration backed up: $BACKUP_FILE"
fi

# Load BBR and FQ modules, persist across reboots.
modprobe tcp_bbr 2>/dev/null || true
modprobe sch_fq 2>/dev/null || true

BBR_SUPPORTED=0
AVAILABLE_CC="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
grep -qw "bbr" <<< "$AVAILABLE_CC" && BBR_SUPPORTED=1

FQ_SUPPORTED=0
if [[ -d /sys/module/sch_fq ]] || modprobe -n sch_fq >/dev/null 2>&1; then
    FQ_SUPPORTED=1
fi

{
    [[ "$BBR_SUPPORTED" -eq 1 ]] && echo "tcp_bbr"
    [[ "$FQ_SUPPORTED" -eq 1 ]] && echo "sch_fq"
} > "$MODULES_CONF"
[[ -s "$MODULES_CONF" ]] || rm -f "$MODULES_CONF"

# Build configuration.
TMP_CONFIG="$(mktemp)"
trap 'rm -f "$TMP_CONFIG"' EXIT

{
    echo "# OP VPS Optimizer - Streaming profile"
    echo "# Managed configuration - generated automatically."
    echo
    echo "# Large buffers for high-latency links (Ghana <-> VPS)"
    echo "net.core.rmem_max = 67108864"
    echo "net.core.wmem_max = 67108864"
    echo "net.core.rmem_default = 262144"
    echo "net.core.wmem_default = 262144"
    echo "net.ipv4.tcp_rmem = 4096 262144 67108864"
    echo "net.ipv4.tcp_wmem = 4096 262144 67108864"
    echo "net.ipv4.udp_rmem_min = 16384"
    echo "net.ipv4.udp_wmem_min = 16384"
    echo
    echo "# Queues and backlogs"
    echo "net.core.netdev_max_backlog = 50000"
    echo "net.core.somaxconn = 65535"
    echo "net.ipv4.tcp_max_syn_backlog = 16384"
    echo
    echo "# TCP behavior"
    echo "net.ipv4.tcp_slow_start_after_idle = 0"
    echo "net.ipv4.tcp_notsent_lowat = 131072"
    echo "net.ipv4.tcp_mtu_probing = 1"
    echo "net.ipv4.tcp_fastopen = 3"
    echo "net.ipv4.tcp_no_metrics_save = 1"
    echo "net.ipv4.tcp_tw_reuse = 1"
    echo "net.ipv4.tcp_fin_timeout = 15"

    if [[ -e /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        echo
        echo "# Connection tracking (UDP tunnels / many customers)"
        echo "net.netfilter.nf_conntrack_max = 1048576"
        echo "net.netfilter.nf_conntrack_udp_timeout_stream = 120"
    fi

    if [[ "$BBR_SUPPORTED" -eq 1 ]]; then
        echo
        echo "net.ipv4.tcp_congestion_control = bbr"
    fi
    if [[ "$FQ_SUPPORTED" -eq 1 ]]; then
        echo "net.core.default_qdisc = fq"
    fi
} > "$TMP_CONFIG"

install -m 0644 "$TMP_CONFIG" "$CONFIG"

# Apply key by key; skip anything this VPS kernel rejects.
echo
echo "Applying OP VPS Optimizer settings..."
FAILED=0
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    val="${line#*=}";  val="${val#"${val%%[![:space:]]*}"}"
    if ! sysctl -w "$key=$val" >/dev/null 2>&1; then
        echo "  skipped: $line"
        FAILED=$((FAILED+1))
    fi
done < "$CONFIG"

# Interface boost: txqueuelen, fq on NIC, MSS clamp (re-applied at boot).
cat > "$BOOST_BIN" <<'BOOST'
#!/usr/bin/env bash
IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')"
if [[ -n "$IFACE" ]]; then
    ip link set dev "$IFACE" txqueuelen 10000 2>/dev/null || true
    if command -v tc >/dev/null 2>&1; then
        tc qdisc show dev "$IFACE" 2>/dev/null | grep -qw fq || tc qdisc replace dev "$IFACE" root fq 2>/dev/null || true
    fi
    command -v ethtool >/dev/null 2>&1 && ethtool -K "$IFACE" gro on gso on tso on >/dev/null 2>&1 || true
fi
if command -v iptables >/dev/null 2>&1; then
    for chain in FORWARD OUTPUT; do
        iptables -t mangle -C "$chain" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
          || iptables -t mangle -A "$chain" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    done
fi
exit 0
BOOST
chmod 0755 "$BOOST_BIN"

cat > "$BOOST_SERVICE" <<EOF
[Unit]
Description=OP VPS Optimizer interface boost
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BOOST_BIN

[Install]
WantedBy=multi-user.target
EOF

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable --now op-stream-boost.service >/dev/null 2>&1 || "$BOOST_BIN"
else
    "$BOOST_BIN"
fi

echo
echo "======================================"
echo "       OP VPS OPTIMIZER COMPLETE"
echo "======================================"
echo "Operating system: ${PRETTY_NAME:-Unknown}"
echo "Congestion ctrl:  $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
echo "Queue discipline: $(sysctl -n net.core.default_qdisc 2>/dev/null)"
echo "TCP receive buf:  $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
echo "TCP send buf:     $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
echo "Skipped settings: $FAILED"
echo "Configuration:    $CONFIG"
echo
echo "Check:     sudo op-vps-optimizer status"
echo "Rollback:  sudo op-vps-optimizer rollback"
echo "======================================"
