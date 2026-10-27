
#!/usr/bin/env bash
# OP-VPS Optimizer - OfficialOnePesewa
set -Eeuo pipefail

REPO="https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main"
BASE="/opt/op-vps-optimizer"
BIN="/usr/local/bin/opvps"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash install.sh"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: This installer supports Debian/Ubuntu with apt-get."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl iproute2 procps coreutils

mkdir -p "$BASE/scripts" "$BASE/config" "$BASE/backups"

download() {
  local path="$1"
  local dest="$2"
  echo "[OPVPS] Downloading $path"
  curl --fail --silent --show-error --location \
    --retry 3 --connect-timeout 15 \
    "$REPO/$path" -o "$dest"
  test -s "$dest"
}

download scripts/optimize.sh "$BASE/scripts/optimize.sh"
download scripts/diagnose.sh "$BASE/scripts/diagnose.sh"
download scripts/rollback.sh "$BASE/scripts/rollback.sh"
download scripts/install-badvpn.sh "$BASE/scripts/install-badvpn.sh"
download config/99-op-vps-optimizer.conf \
  "$BASE/config/99-op-vps-optimizer.conf"

chmod 750 "$BASE/scripts/"*.sh

cat > "$BIN" <<'COMMAND'
#!/usr/bin/env bash
set -Eeuo pipefail
BASE="/opt/op-vps-optimizer"
case "${1:-help}" in
  optimize)
    exec "$BASE/scripts/optimize.sh" ;;
  diagnose|status)
    exec "$BASE/scripts/diagnose.sh" ;;
  rollback)
    exec "$BASE/scripts/rollback.sh" ;;
  badvpn)
    exec "$BASE/scripts/install-badvpn.sh" ;;
  help|-h|--help)
    cat <<'HELP'
OP-VPS Optimizer - OfficialOnePesewa
Usage: opvps <command>

  optimize   Apply persistent network tuning
  diagnose   Show network and server diagnostics
  badvpn     Install/build BadVPN UDPGW
  rollback   Remove this project's tuning
  help       Show this help
HELP
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run: opvps help"
    exit 2
    ;;
esac
COMMAND

chmod 755 "$BIN"

echo
echo "OP-VPS Optimizer installed."
echo "Next: opvps diagnose"
echo "Then: opvps optimize"
echo "BadVPN is optional: opvps badvpn"
