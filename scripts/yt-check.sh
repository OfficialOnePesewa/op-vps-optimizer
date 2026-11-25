#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: YouTube open-time check
# Shows where time goes: DNS, TCP connect, TLS handshake, and first byte.
# Run it on the VPS to measure the server side.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/common.sh"

HOSTS="www.youtube.com i.ytimg.com redirector.googlevideo.com"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required. Install it and try again."
  exit 1
fi

echo "== YouTube open-time check (times in ms) =="
echo "host                          dns    connect  tls    first-byte  total"
for host in $HOSTS; do
  for run in 1 2 3; do
    out="$(curl -o /dev/null -s -m 15 \
      -w '%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}' \
      "https://$host/" 2>/dev/null)"
    if [ -z "$out" ] || [ "$out" = "0.000000 0.000000 0.000000 0.000000 0.000000" ]; then
      printf '%-28s run %s: failed (blocked or unreachable)\n' "$host" "$run"
      continue
    fi
    echo "$out" | awk -v h="$host" -v r="$run" '{
      printf "%-28s %-3s %-6d %-8d %-6d %-11d %d\n", h, r, $1*1000, $2*1000, $3*1000, $4*1000, $5*1000
    }'
  done
done

echo
echo "How to read it:"
echo "- dns high: set a faster resolver in the customer's app, or a caching resolver on the VPS"
echo "- connect or tls high: the route or the tunnel MTU is the problem; op-optimize applies the MSS clamp"
echo "- first-byte high on a good connect: the server path is slow; check op-bench and the VPS location"
