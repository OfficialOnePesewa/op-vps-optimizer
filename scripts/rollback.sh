#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUP_DIR="/var/backups/op-vps-optimizer"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this command as root or with sudo."
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "Optimizer configuration is not installed."
    exit 0
fi

LATEST_BACKUP=""

if [[ -d "$BACKUP_DIR" ]]; then
    LATEST_BACKUP="$(
        find "$BACKUP_DIR" -maxdepth 1 -type f \
            -name '99-op-vps-optimizer.conf.*' \
            -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d ' ' -f 2-
    )"
fi

if [[ -n "$LATEST_BACKUP" && -f "$LATEST_BACKUP" ]]; then
    cp -a "$LATEST_BACKUP" "$CONFIG"
    echo "Restored previous optimizer configuration:"
    echo "$LATEST_BACKUP"
else
    rm -f "$CONFIG"
    echo "Removed optimizer configuration."
fi

echo "Reloading the managed sysctl configuration..."

if [[ -f "$CONFIG" ]]; then
    sysctl -p "$CONFIG"
else
    echo "The optimizer configuration has been removed."
    echo "Other system sysctl files have not been changed."
fi

echo
echo "Rollback completed."
echo "Note: this does not uninstall BadVPN or alter firewall rules."
