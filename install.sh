#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition bootstrap
# Usage: curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | sudo bash
set -uo pipefail

REPO="https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main"
LIB_DIR="/usr/local/lib/op-vps-optimizer"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: curl ... | sudo bash"
  exit 1
fi

# Install curl if the image doesn't have it
if ! command -v curl >/dev/null 2>&1; then
  echo "[*] Installing curl..."
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed curl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl
  else
    echo "curl is missing and no known package manager was found."
    exit 1
  fi
fi

echo "[*] Downloading OP VPS Optimizer files..."
mkdir -p "$LIB_DIR" /usr/local/sbin
for f in common.sh optimize.sh status.sh rollback.sh bench.sh yt-check.sh; do
  if ! curl -fsSL "$REPO/scripts/$f" -o "$LIB_DIR/$f"; then
    echo "Download failed: scripts/$f"
    exit 1
  fi
done
chmod 755 "$LIB_DIR"/*.sh

# Command wrappers
for pair in optimize:op-optimize status:op-status rollback:op-rollback bench:op-bench yt-check:op-ytcheck; do
  src="${pair%%:*}"
  name="${pair##*:}"
  printf '#!/usr/bin/env bash\nexec %s/%s.sh "$@"\n' "$LIB_DIR" "$src" > "/usr/local/sbin/$name"
  chmod 755 "/usr/local/sbin/$name"
done

"$LIB_DIR/optimize.sh"

echo
echo "Installed. Commands: op-status | op-bench | op-ytcheck | op-rollback | op-optimize"
