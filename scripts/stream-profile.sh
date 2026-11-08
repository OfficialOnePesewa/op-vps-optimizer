#!/usr/bin/env bash
set -u

CONF_DIR="/etc/op-vps-optimizer"
MODE_FILE="$CONF_DIR/profile.mode"
STATE_FILE="/run/op-stream-profile.state"
SERVICE="op-stream-adapt.service"
UNIT="/etc/systemd/system/$SERVICE"
SELF="$(readlink -f "$0")"
MSS_COMMENT="op-stream-mss"

need_root() {
    [[ "${EUID}" -eq 0 ]] || { echo "Run this command as root or with sudo."; exit 1; }
}

apply_sysctl() {
    local kv
    for kv in "$@"; do sysctl -w "$kv" >/dev/null 2>&1 || true; done
}

clear_mss() {
    command -v iptables >/dev/null 2>&1 || return 0
    local chain r
    for chain in FORWARD OUTPUT; do
        iptables -t mangle -S "$chain" 2>/dev/null | grep -- "--comment $MSS_COMMENT" |
        while read -r r; do iptables -t mangle ${r/#-A/-D} 2>/dev/null || true; done
    done
}

set_mss() {
    command -v iptables >/dev/null 2>&1 || return 0
    clear_mss
    local chain
    for chain in FORWARD OUTPUT; do
        iptables -t mangle -A "$chain" -p tcp --tcp-flags SYN,RST SYN \
            -m comment --comment "$MSS_COMMENT" -j TCPMSS --set-mss "$1" 2>/dev/null || true
    done
}

default_route_base() {
    ip route show default 2>/dev/null | head -n1 |
        sed -E 's/ initcwnd [0-9]+//; s/ initrcvwnd [0-9]+//'
}

set_initcwnd() {
    local base
    base="$(default_route_base)"
    [[ -n "$base" ]] || return 0
    ip route change $base initcwnd "$1" initrcvwnd "$1" 2>/dev/null || true
}

reset_initcwnd() {
    local base
    base="$(default_route_base)"
    [[ -n "$base" ]] || return 0
    ip route change $base 2>/dev/null || true
}

apply_profile() {
    local lowat limit mss cwnd
    case "$1" in
        lte)   lowat=131072; limit=1048576; mss=1400; cwnd=30 ;;
        hplus) lowat=65536;  limit=524288;  mss=1360; cwnd=16 ;;
        *) return 1 ;;
    esac
    apply_sysctl \
        net.ipv4.tcp_notsent_lowat="$lowat" \
        net.ipv4.tcp_limit_output_bytes="$limit" \
        net.ipv4.tcp_sack=1 net.ipv4.tcp_dsack=1 \
        net.ipv4.tcp_frto=2 net.ipv4.tcp_autocorking=0
    set_mss "$mss"
    set_initcwnd "$cwnd"
    echo "$1" > "$STATE_FILE"
    logger -t op-smartflow "profile applied: $1" 2>/dev/null || true
}

read_tcp() {
    awk '/^Tcp:/{ if(!h){split($0,n);h=1} else {
            for(i=1;i<=NF;i++){ if(n[i]=="OutSegs")o=$i; if(n[i]=="RetransSegs")r=$i } } }
         END{print o+0, r+0}' /proc/net/snmp
}

daemon() {
    local mode current bad good po pr o r dO dR pm
    mode="$(cat "$MODE_FILE" 2>/dev/null || echo auto)"
    case "$mode" in
        lte|hplus) apply_profile "$mode"; exec sleep infinity ;;
    esac

    current="lte"; apply_profile lte
    read -r po pr < <(read_tcp)
    bad=0; good=0
    while true; do
        sleep 20
        read -r o r < <(read_tcp)
        dO=$((o - po)); dR=$((r - pr)); po=$o; pr=$r
        (( dO < 300 )) && continue
        pm=$(( dR * 1000 / dO ))            # retransmits per 1000 segments
        if   (( pm >= 30 )); then bad=$((bad+1)); good=0
        elif (( pm <= 10 )); then good=$((good+1)); bad=0
        else bad=0; good=0; fi
        if (( bad >= 3 )) && [[ "$current" != "hplus" ]]; then
            current="hplus"; apply_profile hplus; bad=0
        elif (( good >= 6 )) && [[ "$current" != "lte" ]]; then
            current="lte"; apply_profile lte; good=0
        fi
    done
}

install_service() {
    mkdir -p "$CONF_DIR"
    echo "$1" > "$MODE_FILE"
    cat > "$UNIT" <<EOF
[Unit]
Description=OP SmartFlow adaptive streaming profile
After=network-online.target op-stream-boost.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SELF daemon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE" >/dev/null 2>&1 || true
    systemctl restart "$SERVICE"
    echo "OP SmartFlow mode set to: $1"
}

turn_off() {
    systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    rm -f "$UNIT" "$MODE_FILE" "$STATE_FILE"
    systemctl daemon-reload 2>/dev/null || true
    clear_mss
    reset_initcwnd
    apply_sysctl net.ipv4.tcp_limit_output_bytes=1048576
    sysctl --system >/dev/null 2>&1 || true
    echo "OP SmartFlow turned off. Base optimizer settings restored."
}

show_status() {
    local o1 r1 o2 r2 dO dR
    echo "SmartFlow mode:     $(cat "$MODE_FILE" 2>/dev/null || echo off)"
    echo "Active profile:     $(cat "$STATE_FILE" 2>/dev/null || echo none)"
    echo "Service:            $(systemctl is-active "$SERVICE" 2>/dev/null || echo inactive)"
    read -r o1 r1 < <(read_tcp); sleep 5; read -r o2 r2 < <(read_tcp)
    dO=$((o2 - o1)); dR=$((r2 - r1))
    if (( dO > 0 )); then
        echo "Retransmits (5s):   $dR of $dO segments (~$(( dR * 1000 / dO )) per 1000)"
    else
        echo "Retransmits (5s):   no traffic measured"
    fi
}

case "${1:-help}" in
    auto|lte|hplus) need_root; install_service "$1" ;;
    off)            need_root; turn_off ;;
    status)         show_status ;;
    daemon)         need_root; daemon ;;
    *)
        cat <<'EOF'
OP SmartFlow - adaptive streaming profiles

  op-vps-optimizer profile auto     Switch automatically (recommended)
  op-vps-optimizer profile lte      Force the LTE profile
  op-vps-optimizer profile hplus    Force the H+ / lossy-link profile
  op-vps-optimizer profile status   Show mode, active profile, retransmits
  op-vps-optimizer profile off      Disable SmartFlow
EOF
        ;;
esac
