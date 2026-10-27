
#!/usr/bin/env bash
# OP-VPS Optimizer | OfficialOnePesewa
set -Eeuo pipefail

CONF="/etc/sysctl.d/99-op-vps-optimizer.conf"
BACKUPS="/opt/op-vps-optimizer/backups"

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

echo "This removes the OP-VPS Optimizer sysctl configuration."
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

rm -f "$CONF"

# Restore the most recent saved configuration, if one exists.
shopt -s nullglob
files=("$BACKUPS"/config-before-*.conf)

if ((${#files[@]})); then
  latest="$(printf '%s\n' "${files[@]}" | sort | tail -n 1)"
  cp -a "$latest" "$CONF"
  echo "Restored: $latest"
else
  echo "No previous project configuration was saved."
  echo "Other sysctl files and manual changes remain untouched."
fi

sysctl --system
echo "Rollback finished."
echo "Note: BadVPN remains installed. It is not removed by this command."
