#!/usr/bin/env bash
# OP VPS Optimizer - shared helpers
# Supports Debian, Ubuntu, AlmaLinux, Rocky, RHEL, CentOS, Oracle, Amazon Linux,
# Fedora, Arch, Alpine, openSUSE and most other systemd or OpenRC Linux VPS images.

OP_BACKUP_DIR="/var/backups/op-vps-optimizer"
OP_SYSCTL_FILE="/etc/sysctl.d/99-op-vps-optimizer.conf"
OP_LIMITS_FILE="/etc/security/limits.d/99-op-vps-optimizer.conf"
OP_PROTECTED_PORTS="7100 7200 7300"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (use sudo)."
    exit 1
  fi
}

detect_os() {
  OS_ID="unknown"
  OS_LIKE=""
  OS_VERSION=""
  OS_PRETTY="unknown Linux"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
    OS_VERSION="${VERSION_ID:-}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
  fi

  local ids=" $OS_ID $OS_LIKE "
  PKG=""
  case "$ids" in
    *" debian "*|*" ubuntu "*)
      PKG="apt" ;;
    *" rhel "*|*" centos "*|*" fedora "*|*" almalinux "*|*" rocky "*|*" ol "*|*" amzn "*)
      if command -v dnf >/dev/null 2>&1; then PKG="dnf"; else PKG="yum"; fi ;;
    *" arch "*)
      PKG="pacman" ;;
    *" alpine "*)
      PKG="apk" ;;
    *suse*)
      PKG="zypper" ;;
  esac

  # Fallback: detect by which package manager exists
  if [ -z "$PKG" ]; then
    for b in apt-get dnf yum pacman apk zypper; do
      if command -v "$b" >/dev/null 2>&1; then
        case "$b" in
          apt-get) PKG="apt" ;;
          dnf)     PKG="dnf" ;;
          yum)     PKG="yum" ;;
          pacman)  PKG="pacman" ;;
          apk)     PKG="apk" ;;
          zypper)  PKG="zypper" ;;
        esac
        break
      fi
    done
  fi
  [ -n "$PKG" ] || PKG="none"
}

pkg_install() {
  case "$PKG" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 </dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" </dev/null ;;
    dnf)    dnf install -y -q "$@" </dev/null ;;
    yum)    yum install -y -q "$@" </dev/null ;;
    pacman) pacman -Sy --noconfirm --needed "$@" </dev/null ;;
    apk)    apk add --no-cache "$@" </dev/null ;;
    zypper) zypper --non-interactive install "$@" </dev/null ;;
    *)      return 1 ;;
  esac
}

ss_pkg() {
  case "$PKG" in
    dnf|yum) echo "iproute" ;;
    *)       echo "iproute2" ;;
  esac
}

ensure_deps() {
  local need=""
  command -v curl >/dev/null 2>&1 || need="$need curl"
  command -v ss >/dev/null 2>&1 || need="$need $(ss_pkg)"
  [ -z "$need" ] && return 0
  echo "[*] Installing missing tools:$need"
  # shellcheck disable=SC2086
  pkg_install $need || echo "[!] Could not install:$need (port checks may show unknown)"
}

check_virt() {
  VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"
  if [ -f /proc/user_beancounters ]; then
    VIRT="openvz"
  fi
  case "$VIRT" in
    openvz|lxc|lxc-libvirt|docker|podman|wsl)
      echo "[!] Virtualization: $VIRT. The host kernel controls TCP settings, so some values may be refused. Applying what is allowed."
      ;;
    *)
      echo "[*] Virtualization: $VIRT" ;;
  esac
}

save_originals() {
  mkdir -p "$OP_BACKUP_DIR"
  if [ ! -f "$OP_BACKUP_DIR/original.env" ]; then
    {
      echo "ORIG_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo cubic)"
      echo "ORIG_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo pfifo_fast)"
    } > "$OP_BACKUP_DIR/original.env"
    echo "[*] Saved original values to $OP_BACKUP_DIR/original.env"
  fi
}

# Apply a sysctl file key by key, so unsupported keys are skipped instead of aborting
apply_sysctl_file() {
  local ok=0 skip=0 key val
  while IFS='=' read -r key val; do
    key="${key%% *}"
    val="${val# }"
    case "$key" in
      ""|\#*) continue ;;
    esac
    if sysctl -w "$key=$val" >/dev/null 2>&1; then
      ok=$((ok + 1))
    else
      skip=$((skip + 1))
      echo "    skipped $key (not supported on this kernel or VPS)"
    fi
  done < "$1"
  echo "    applied $ok settings, skipped $skip"
}

port_state() {
  if command -v ss >/dev/null 2>&1; then
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"; then echo "up"; else echo "down"; fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"; then echo "up"; else echo "down"; fi
  else
    echo "unknown"
  fi
}

restore_originals() {
  if [ -f "$OP_BACKUP_DIR/original.env" ]; then
    # shellcheck disable=SC1091
    . "$OP_BACKUP_DIR/original.env"
    sysctl -w net.ipv4.tcp_congestion_control="$ORIG_CC" >/dev/null 2>&1
    sysctl -w net.core.default_qdisc="$ORIG_QDISC" >/dev/null 2>&1
    rm -f "$OP_BACKUP_DIR/original.env"
  fi
  # Buffer values go back to typical kernel defaults. A reboot restores every default.
  sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1
  sysctl -w net.core.wmem_max=212992 >/dev/null 2>&1
  sysctl -w net.ipv4.tcp_rmem="4096 131072 6291456" >/dev/null 2>&1
  sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null 2>&1
}
