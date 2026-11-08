#!/usr/bin/env bash
set -u

CONF="/etc/sysctl.d/99-op-turbo.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"
ORIG="$BACKUP_DIR/turbo-original.conf"
RING_ORIG="$BACKUP_DIR/turbo-ring.orig"
HASH_ORIG="$BACKUP_DIR/turbo-hashsize.orig"
UNIT="/etc/systemd/system/op-turbo.service"
HASHSIZE_FILE="/sys/module/nf_conntrack/parameters/hashsize"
SELF="$(readlink -f "$0")"
KEYS=(
    fs.file-max
    net.ipv4.ip_local_port_range
    net.ipv4.tcp_max_tw_buckets
    net.core.optmem_max
    net.core.rps_sock_flow_entries
)

need_root() {
    [[ "${EUID}" -eq 0 ]] || { echo "Run this command as root or with sudo."; exit 1; }
}

iface() {
    ip route get 1.1.1.1 2>/dev/null |
        awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}'
}

set_kv_file() {
    local line key val
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        key="${line%%=*}"; key="${key//[[:space:]]/}"
        val="${line#*=}";  val="${val#"${val%%[![:space:]]*}"}"
        sysctl -w "$key=$val" >/dev/null 2>&1 || echo "  skipped: $key"
    done < "$1"
}

nic_tune() {
    local IF g rxmax txmax rxcur txcur cores mask nq q
    IF="$(iface)"
    [[ -n "$IF" ]] || return 0

    # 1) Larger NIC rings (many VPS NICs refuse this - that is fine)
    if command -v ethtool >/dev/null 2>&1; then
        g="$(ethtool -g "$IF" 2>/dev/null || true)"
        if [[ -n "$g" ]]; then
            rxmax="$(awk '/Pre-set maximums/{m=1;next} /Current hardware/{m=0} m&&/^RX:/{print $2;exit}' <<<"$g")"
            txmax="$(awk '/Pre-set maximums/{m=1;next} /Current hardware/{m=0} m&&/^TX:/{print $2;exit}' <<<"$g")"
            rxcur="$(awk '/Current hardware/{c=1;next} c&&/^RX:/{print $2;exit}' <<<"$g")"
            txcur="$(awk '/Current hardware/{c=1;next} c&&/^TX:/{print $2;exit}' <<<"$g")"
            if [[ "$rxmax" =~ ^[0-9]+$ && "$txmax" =~ ^[0-9]+$ && "$rxcur" =~ ^[0-9]+$ && "$txcur" =~ ^[0-9]+$ ]]; then
                [[ -f "$RING_ORIG" ]] || echo "$rxcur $txcur" > "$RING_ORIG"
                ethtool -G "$IF" rx "$rxmax" tx "$txmax" >/dev/null 2>&1 || true
            fi
        fi
    fi

    # 2) fq with room for bulk flows
    command -v tc >/dev/null 2>&1 && \
        tc qdisc replace dev "$IF" root fq limit 20000 flow_limit 500 2>/dev/null || true

    # 3) Spread packet processing across all CPU cores (RPS/RFS)
    cores="$(nproc 2>/dev/null || echo 1)"
    (( cores > 32 )) && cores=32
    if (( cores > 1 )); then
        mask="$(printf '%x' $(( (1 << cores) - 1 )))"
        nq=0
        for q in /sys/class/net/"$IF"/queues/rx-*; do
            [[ -e "$q/rps_cpus" ]] && nq=$((nq+1))
        done
        (( nq > 0 )) || nq=1
        for q in /sys/class/net/"$IF"/queues/rx-*; do
            [[ -e "$q/rps_cpus" ]] || continue
            echo "$mask" > "$q/rps_cpus" 2>/dev/null || true
            echo $(( 32768 / nq )) > "$q/rps_flow_cnt" 2>/dev/null || true
        done
    fi

    # 4) Bigger conntrack hash table for many parallel connections
    modprobe nf_conntrack 2>/dev/null || true
    if [[ -w "$HASHSIZE_FILE" ]]; then
        [[ -f "$HASH_ORIG" ]] || cat "$HASHSIZE_FILE" > "$HASH_ORIG" 2>/dev/null || true
        echo 262144 > "$HASHSIZE_FILE" 2>/dev/null || true
    fi
}

turbo_on() {
    mkdir -p "$BACKUP_DIR"
    if [[ ! -f "$ORIG" ]]; then
        : > "$ORIG"
        local k v
        for k in "${KEYS[@]}"; do
            v="$(sysctl -n "$k" 2>/dev/null || true)"
            [[ -n "$v" ]] && echo "$k = $v" >> "$ORIG"
        done
    fi
    cat > "$CONF" <<'EOF'
# OP Turbo - heavy download profile
fs.file-max = 2097152
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.core.optmem_max = 1048576
net.core.rps_sock_flow_entries = 32768
EOF
    set_kv_file "$CONF"
    nic_tune

    cat > "$UNIT" <<EOF
[Unit]
Description=OP Turbo network queues
After=network-online.target op-stream-boost.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SELF _apply

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable op-turbo.service >/dev/null 2>&1 || true
    echo "OP Turbo is on."
}

turbo_off() {
    local IF q rx tx
    IF="$(iface)"
    systemctl disable --now op-turbo.service >/dev/null 2>&1 || true
    rm -f "$UNIT" "$CONF"
    systemctl daemon-reload 2>/dev/null || true

    [[ -f "$ORIG" ]] && set_kv_file "$ORIG"

    if [[ -n "$IF" ]]; then
        for q in /sys/class/net/"$IF"/queues/rx-*; do
            [[ -e "$q/rps_cpus" ]] || continue
            echo 0 > "$q/rps_cpus" 2>/dev/null || true
            echo 0 > "$q/rps_flow_cnt" 2>/dev/null || true
        done
        if [[ -f "$RING_ORIG" ]] && command -v ethtool >/dev/null 2>&1; then
            read -r rx tx < "$RING_ORIG"
            ethtool -G "$IF" rx "$rx" tx "$tx" >/dev/null 2>&1 || true
        fi
        command -v tc >/dev/null 2>&1 && \
            tc qdisc replace dev "$IF" root fq 2>/dev/null || true
    fi

    if [[ -f "$HASH_ORIG" && -w "$HASHSIZE_FILE" ]]; then
        cat "$HASH_ORIG" > "$HASHSIZE_FILE" 2>/dev/null || true
    fi

    rm -f "$ORIG" "$RING_ORIG" "$HASH_ORIG"
    echo "OP Turbo is off. Original values restored."
}

show_status() {
    local IF k q
    IF="$(iface)"
    echo "OP Turbo:           $([[ -f "$CONF" ]] && echo ON || echo OFF)"
    echo "Interface:          ${IF:-unknown}   CPU cores: $(nproc 2>/dev/null)"
    for k in "${KEYS[@]}"; do
        printf '%-40s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo n/a)"
    done
    [[ -r "$HASHSIZE_FILE" ]] && echo "conntrack hashsize: $(cat "$HASHSIZE_FILE")"
    if [[ -n "$IF" ]]; then
        for q in /sys/class/net/"$IF"/queues/rx-*; do
            [[ -e "$q/rps_cpus" ]] && echo "$(basename "$q") rps_cpus: $(cat "$q/rps_cpus")"
        done
        command -v tc >/dev/null 2>&1 && tc qdisc show dev "$IF" 2>/dev/null | head -n1
        command -v ethtool >/dev/null 2>&1 && ethtool -g "$IF" 2>/dev/null | sed -n '/Current hardware/,$p'
    fi
}

case "${1:-help}" in
    on)      need_root; turbo_on ;;
    off)     need_root; turbo_off ;;
    status)  show_status ;;
    _apply)  nic_tune ;;
    *)
        cat <<'EOF'
OP Turbo - heavy download profile

  op-vps-optimizer turbo on       Enable
  op-vps-optimizer turbo off      Disable and restore original values
  op-vps-optimizer turbo status   Show current state
EOF
        ;;
esac
