#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"
ORIG="$BACKUP_DIR/sysctl-original.conf"
BOOST_BIN="/usr/local/sbin/op-stream-boost"
BOOST_SERVICE="/etc/systemd/system/op-stream-boost.service"
MODULES_CONF="/etc/modules-load.d/op-vps-optimizer.conf"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

FULL=0
[[ "${1:-}" == "--full" ]] && FULL=1

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this command as root or with sudo."
    exit 1
fi

echo "Rolling back OP VPS Optimizer..."

# 0) Turn off OP SmartFlow first, so restored values below take priority.
if [[ -x "$SCRIPT_DIR/stream-profile.sh" ]]; then
    "$SCRIPT_DIR/stream-profile.sh" off >/dev/null 2>&1 || true
else
    systemctl disable --now op-stream-adapt.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/op-stream-adapt.service \
          /etc/op-vps-optimizer/profile.mode /run/op-stream-profile.state
fi
sysctl -w net.ipv4.tcp_autocorking=1 >/dev/null 2>&1 || true
echo "OP SmartFlow removed."

# 1) Restore original live kernel values, key by key.
if [[ -f "$ORIG" ]]; then
    RESTORED=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        key="${line%% =*}"
        val="${line#*= }"
        if sysctl -w "$key=$val" >/dev/null 2>&1; then
            RESTORED=$((RESTORED+1))
        fi
    done < "$ORIG"
    echo "Restored $RESTORED original kernel values."
else
    echo "No original values saved - settings return to defaults after reboot."
fi

# 2) Remove the managed sysctl file.
rm -f "$CONFIG"

# 3) Remove the interface boost service, script and MSS clamp rules.
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now op-stream-boost.service >/dev/null 2>&1 || true
fi
rm -f "$BOOST_SERVICE" "$BOOST_BIN" "$MODULES_CONF"

if command -v iptables >/dev/null 2>&1; then
    for chain in FORWARD OUTPUT; do
        while iptables -t mangle -D "$chain" -p tcp --tcp-flags SYN,RST SYN \
              -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; do :; done
    done
fi

# 4) Optional: remove BadVPN services created by this project.
if [[ "$FULL" -eq 1 ]]; then
    echo "Removing OP BadVPN-UDPGW services..."
    for p in 7100 7200 7300; do
        systemctl disable --now "op-badvpn-udpgw@${p}.service" >/dev/null 2>&1 || true
    done
    systemctl disable --now op-badvpn-udpgw.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/op-badvpn-udpgw@.service \
          /etc/systemd/system/op-badvpn-udpgw.service
fi

command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

echo
echo "Rollback completed."
if [[ "$FULL" -eq 1 ]]; then
    echo "BadVPN-UDPGW services removed."
else
    echo "BadVPN-UDPGW was left running. Use: op-vps-optimizer rollback --full"
fi
echo "Your ZIVPN, UDP Custom and other firewall rules were not touched."
echo "A reboot is not required."
