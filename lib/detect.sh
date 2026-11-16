#!/usr/bin/env bash
# 🧩 lib/detect.sh v2.2.0 - universal VPS provider + OS detection (ipapi.co)
# Author: OfficialOnePesewa · Telegram: @OfficialOnePesewa

OP_AUTHOR="OfficialOnePesewa"
OP_TELEGRAM="@OfficialOnePesewa"
OP_VERSION="2.2.0"

# ---------- OS ----------
op_detect_os() {
  OS_PRETTY="unknown"; OS_ID="unknown"; OS_VERSION="unknown"
  if [ -r /etc/os-release ]; then
    OS_PRETTY="$(. /etc/os-release; echo "${PRETTY_NAME:-unknown}")"
    OS_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
    OS_VERSION="$(. /etc/os-release; echo "${VERSION_ID:-unknown}")"
  fi
  KERNEL="$(uname -r)"
  ARCH="$(uname -m)"
}

# ---------- Helpers ----------
op_http() { curl -fsS --max-time 5 "$@" 2>/dev/null; }

# Map any text (vendor, hostname, network owner) to a clean provider name
op_name_from_text() {
  local t
  t="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    *contabo*)                     echo "Contabo" ;;
    *hetzner*)                     echo "Hetzner" ;;
    *digitalocean*)                echo "DigitalOcean" ;;
    *vultr*|*choopa*)              echo "Vultr" ;;
    *linode*|*akamai*)             echo "Linode (Akamai)" ;;
    *amazon*|*aws*)                echo "Amazon AWS" ;;
    *google*)                      echo "Google Cloud" ;;
    *microsoft*|*azure*)           echo "Microsoft Azure" ;;
    *oracle*)                      echo "Oracle Cloud" ;;
    *ovh*)                         echo "OVHcloud" ;;
    *scaleway*|*online.net*)       echo "Scaleway" ;;
    *kamatera*)                    echo "Kamatera" ;;
    *alibaba*|*aliyun*)            echo "Alibaba Cloud" ;;
    *tencent*)                     echo "Tencent Cloud" ;;
    *upcloud*)                     echo "UpCloud" ;;
    *racknerd*)                    echo "RackNerd" ;;
    *ionos*)                       echo "IONOS" ;;
    *gcore*)                       echo "Gcore" ;;
    *hostinger*)                   echo "Hostinger" ;;
    *netcup*)                      echo "netcup" ;;
    *ramnode*)                     echo "RamNode" ;;
    *hostwinds*)                   echo "Hostwinds" ;;
    *leaseweb*)                    echo "Leaseweb" ;;
    *hosthatch*)                   echo "HostHatch" ;;
    *buyvm*|*frantech*)            echo "BuyVM (FranTech)" ;;
    *dreamhost*)                   echo "DreamHost" ;;
    *godaddy*)                     echo "GoDaddy" ;;
    *namecheap*)                   echo "Namecheap" ;;
    *interserver*)                 echo "InterServer" ;;
    *atlantic*)                    echo "Atlantic.Net" ;;
    *cherry*server*)               echo "CherryServers" ;;
    *equinix*|*packet*)            echo "Equinix Metal" ;;
    *rackspace*)                   echo "Rackspace" ;;
    *cloudflare*)                  echo "Cloudflare" ;;
    *zenlayer*)                    echo "Zenlayer" ;;
    *psychz*)                      echo "Psychz" ;;
    *) ;;
  esac
}

# Public IP of this server
op_public_ip() {
  PUBLIC_IP="$(op_http https://api.ipify.org || op_http https://ifconfig.me || true)"
  PUBLIC_IP="$(echo "$PUBLIC_IP" | tr -d '[:space:]')"
  case "$PUBLIC_IP" in
    *[!0-9.]*|"") PUBLIC_IP="" ;;
  esac
}

# ipapi.co: fetch once per run and cache the JSON
op_ipapi_fetch() {
  [ -n "${IPAPI_JSON:-}" ] && return 0
  IPAPI_JSON="$(op_http "https://ipapi.co/${PUBLIC_IP:-json}/json/")"
  case "$IPAPI_JSON" in
    *'"error"'*|"") IPAPI_JSON="" ;;
  esac
}

# Read one field from the cached ipapi.co JSON
op_ipapi_field() {
  echo "$IPAPI_JSON" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" | head -n1
}

# ---------- Provider detection (layered) ----------
op_metadata_provider() {
  if curl -fsS --max-time 2 -X PUT http://169.254.169.254/latest/api/token \
       -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' >/dev/null 2>&1; then
    echo "Amazon AWS"; return
  fi
  if curl -fsS --max-time 2 -H 'Metadata-Flavor: Google' \
       http://metadata.google.internal/computeMetadata/v1/instance/id >/dev/null 2>&1; then
    echo "Google Cloud"; return
  fi
  if curl -fsS --max-time 2 -H 'Metadata: true' \
       'http://169.254.169.254/metadata/instance?api-version=2021-02-01' >/dev/null 2>&1; then
    echo "Microsoft Azure"; return
  fi
  if curl -fsS --max-time 2 -H 'Authorization: Bearer Oracle' \
       http://169.254.169.254/opc/v2/instance >/dev/null 2>&1; then
    echo "Oracle Cloud"; return
  fi
  if curl -fsS --max-time 2 http://169.254.169.254/hetzner/v1/metadata >/dev/null 2>&1; then
    echo "Hetzner"; return
  fi
  if curl -fsS --max-time 2 http://169.254.169.254/metadata/v1/id >/dev/null 2>&1; then
    echo "DigitalOcean"; return
  fi
}

op_detect_provider() {
  [ -n "${PROVIDER:-}" ] && return 0

  local dmi host raw name
  dmi="$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name \
        /sys/class/dmi/id/bios_vendor /sys/class/dmi/id/board_vendor \
        /sys/class/dmi/id/chassis_vendor /sys/class/dmi/id/chassis_asset_tag 2>/dev/null | tr '\n' ' ')"
  host="$(hostname -f 2>/dev/null || hostname 2>/dev/null)"
  raw="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')"
  VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"

  PROVIDER=""; PROVIDER_SOURCE=""
  ASN_ORG=""; ASN_NUMBER=""; IP_CITY=""; IP_COUNTRY=""
  op_public_ip

  # 1) Cloud metadata (fastest and most accurate on big clouds)
  name="$(op_metadata_provider)"
  if [ -n "$name" ]; then
    PROVIDER="$name"; PROVIDER_SOURCE="cloud metadata"
  fi

  # 2) ipapi.co network owner (works for any provider on the internet)
  op_ipapi_fetch
  if [ -n "$IPAPI_JSON" ]; then
    ASN_ORG="$(op_ipapi_field org)"
    ASN_NUMBER="$(op_ipapi_field asn)"
    IP_CITY="$(op_ipapi_field city)"
    IP_COUNTRY="$(op_ipapi_field country_name)"
    if [ -z "$PROVIDER" ] && [ -n "$ASN_ORG" ]; then
      name="$(op_name_from_text "$ASN_ORG")"
      PROVIDER="${name:-$ASN_ORG}"
      PROVIDER_SOURCE="network owner (ipapi.co)"
    fi
  fi

  # 3) Hardware and hostname (used if ipapi.co is unreachable)
  if [ -z "$PROVIDER" ]; then
    name="$(op_name_from_text "$dmi $host")"
    if [ -n "$name" ]; then
      PROVIDER="$name"; PROVIDER_SOURCE="hardware/hostname"
    fi
  fi

  # 4) Raw vendor fallback
  if [ -z "$PROVIDER" ]; then
    if [ -n "$raw" ]; then
      PROVIDER="Unlisted provider (hardware vendor: $raw)"
    else
      PROVIDER="Unknown provider"
    fi
    PROVIDER_SOURCE="fallback"
  fi
}

op_check_os() {
  case "$OS_ID" in
    debian|ubuntu) return 0 ;;
    *) echo "⚠️  $OS_PRETTY is not Debian or Ubuntu. The script will continue, but it is only tested on those." ;;
  esac
}

# ---------- Display ----------
op_banner() {
  echo "════════════════════════════════════════════════════"
  echo "  🚀 OP VPS OPTIMIZER  ·  Streaming Edition  v$OP_VERSION"
  echo "  ⚡ BBR · Anti-buffering · Fast browsing & downloads"
  echo "  👤 Author: $OP_AUTHOR"
  echo "  ✈️  Telegram: $OP_TELEGRAM"
  echo "════════════════════════════════════════════════════"
}

op_show_system() {
  op_detect_os
  op_detect_provider
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  echo "🖥️  VPS provider   : $PROVIDER"
  echo "🔎 Detected via   : $PROVIDER_SOURCE"
  [ -n "$ASN_ORG" ]     && echo "🏢 Network owner  : $ASN_ORG ${ASN_NUMBER:+($ASN_NUMBER)}"
  [ -n "$IP_COUNTRY" ]  && echo "📍 Location       : ${IP_CITY:+$IP_CITY, }$IP_COUNTRY"
  echo "🐧 Operating sys  : $OS_PRETTY"
  echo "🔢 OS version     : $OS_VERSION ($OS_ID)"
  echo "🧠 Kernel         : $KERNEL ($ARCH)"
  echo "🧪 Virtualization : $VIRT"
  echo "🌐 Private IP     : ${ip:-unknown}"
  echo "🌍 Public IP      : ${PUBLIC_IP:-unknown}"
  op_check_os
}

op_thanks() {
  echo "🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌"
  echo "   ✅ INSTALLATION SUCCESSFUL"
  echo "🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌🙌"
  echo
  echo "   THANKS FOR INSTALLING OP VPS OPTIMIZER SCRIPT ON YOUR SERVER,"
  echo "   HOPE YOU ENJOY IT 😉"
  echo
  echo "   👤 Author   : $OP_AUTHOR"
  echo "   ✈️  Telegram : $OP_TELEGRAM"
  echo
  echo "   📊 Check anytime : sudo op-status"
  echo "   ↩️  Undo anytime  : sudo op-rollback"
}
