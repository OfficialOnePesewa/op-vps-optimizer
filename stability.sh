#!/usr/bin/env bash
set -u

CONF="/etc/sysctl.d/99-op-stability.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"
ORIG="$BACKUP_DIR/stability-original.conf"
UNIT="/etc/systemd/system/op-quic-block.service"
TAG="op-quic-block"
SELF="$(readlink -f "$0")"
KEYS=(
    net.ipv4.tcp_keepalive_time
    net.ipv4.tcp_keepalive_intvl
    net.ipv4.tcp_keepalive_probes
    net.netfilter.nf_conntrack_udp_timeout
    net.netfilter.nf_conntrack_udp_timeout_stream
)

need_root() {
    [[ "${EUID}" -eq 0 ]] || { echo "Run this command as root or with sudo."; exit 1; }
}

set_kv_file() {  # apply "key = value" lines from a file, skipping failures
    local line key val
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        key="${line%%=*}"; key="${key//[[:space:]]/}"
        val="${line#*=}";  val="${val#"${val%%[![:space:]]*}"}"
        sysctl -w "$key=$val" >/dev/null 2>&1 || echo "  skipped: $key"
    done < "$1"
}

apply_stability() {
    mkdir -p "$BACKUP_DIR"
    modprobe nf_conntrack 2>/dev/null || true
    if [[ ! -f "$ORIG" ]]; then
        : > "$ORIG"
        local k v
        for k in "${KEYS[@]}"; do
            v="$(sysctl -n "$k" 2>/dev/null || true)"
            [[ -n "$v" ]] && echo "$k = $v" >> "$ORIG"
        done
    fi
    cat > "$CONF" <<'EOF'
# OP VPS Optimizer - connection stability
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 8
net.netfilter.nf_conntrack_udp_timeout = 90
net.netfilter.nf_conntrack_udp_timeout_stream = 180
EOF
    set_kv_file "$CONF"
    echo "Stability settings applied."
}

block_rules() {
    local bin chain
    for bin in iptables ip6tables; do
        command -v "$bin" >/dev/null 2>&1 || continue
        for chain in FORWARD OUTPUT; do
            "$bin" -C "$chain" -p udp --dport 443 -m comment --comment "$TAG" -j REJECT 2>/dev/null \
              || "$bin" -I "$chain" -p udp --dport 443 -m comment --comment "$TAG" -j REJECT 2>/dev/null || true
        done
    done
}

unblock_rules() {
    local bin chain r
    for bin in iptables ip6tables; do
        command -v "$bin" >/dev/null 2>&1 || continue
        for chain in FORWARD OUTPUT; do
            "$bin" -S "$chain" 2>/dev/null | grep -- "--comment $TAG" |
            while read -r r; do "$bin" ${r/#-A/-D} 2>/dev/null || true; done
        done
    done
}

quic_block() {
    cat > "$UNIT" <<EOF
[Unit]
Description=OP VPS Optimizer QUIC block (UDP 443)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SELF _block
ExecStop=$SELF _unblock

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now op-quic-block.service >/dev/null 2>&1 || block_rules
    echo "QUIC (UDP 443) blocked. Apps now fall back to TCP."
}

quic_allow() {
    systemctl disable --now op-quic-block.service >/dev/null 2>&1 || true
    rm -f "$UNIT"
    systemctl daemon-reload 2>/dev/null || true
    unblock_rules
    echo "QUIC (UDP 443) allowed again."
}

turn_off() {
    quic_allow
    [[ -f "$ORIG" ]] && set_kv_file "$ORIG"
    rm -f "$CONF"
    echo "Stability settings removed and original values restored."
}

show_status() {
    echo "Stability config:   $([[ -f "$CONF" ]] && echo installed || echo "not installed")"
    if iptables -C FORWARD -p udp --dport 443 -m comment --comment "$TAG" -j REJECT 2>/dev/null; then
        echo "QUIC block:         ON (apps use TCP)"
    else
        echo "QUIC block:         OFF"
    fi
    local k
    for k in "${KEYS[@]}"; do
        printf '%-46s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo n/a)"
    done
}

case "${1:-help}" in
    apply)       need_root; apply_stability ;;
    quic-block)  need_root; quic_block ;;
    quic-allow)  need_root; quic_allow ;;
    off)         need_root; turn_off ;;
    status)      show_status ;;
    _block)      block_rules ;;
    _unblock)    unblock_rules ;;
    *)
        cat <<'EOF'
OP VPS Optimizer - connection stability

  op-vps-optimizer stability apply        Longer UDP timeouts and keepalives
  op-vps-optimizer stability quic-block   Block QUIC so apps use TCP (optional)
  op-vps-optimizer stability quic-allow   Allow QUIC again
  op-vps-optimizer stability status       Show current state
  op-vps-optimizer stability off          Remove everything and restore values
EOF
        ;;
esac
