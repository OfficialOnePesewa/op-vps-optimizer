#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: speed test
# Reports MB/s (megabytes per second) and Mbps (megabits per second).
# Uses Cloudflare's public speed endpoints.

to_rates() {
  # $1 = bytes per second
  awk -v b="$1" 'BEGIN {
    if (b + 0 <= 0) { print "failed" ; exit }
    printf "%.2f MB/s  (%.1f Mbps)", b / 1000000, b * 8 / 1000000
  }'
}

echo "== Download (3 runs, 100 MB each) =="
down_total=0
for i in 1 2 3; do
  speed="$(curl -o /dev/null -s -m 90 -w '%{speed_download}' \
    "https://speed.cloudflare.com/__down?bytes=104857600" 2>/dev/null || echo 0)"
  echo "run $i: $(to_rates "${speed:-0}")"
  down_total="$(awk -v a="$down_total" -v b="${speed:-0}" 'BEGIN {print a + b}')"
done
down_avg="$(awk -v t="$down_total" 'BEGIN {print t / 3}')"
echo "average: $(to_rates "$down_avg")"

echo
echo "== Upload (3 runs, 20 MB each) =="
TMP_FILE="$(mktemp /tmp/op-upload-XXXXXX.bin)"
up_total=0
for i in 1 2 3; do
  head -c 20971520 /dev/urandom > "$TMP_FILE"
  speed="$(curl -o /dev/null -s -m 90 -w '%{speed_upload}' \
    -X POST --data-binary @"$TMP_FILE" \
    "https://speed.cloudflare.com/__up" 2>/dev/null || echo 0)"
  echo "run $i: $(to_rates "${speed:-0}")"
  up_total="$(awk -v a="$up_total" -v b="${speed:-0}" 'BEGIN {print a + b}')"
done
rm -f "$TMP_FILE"
up_avg="$(awk -v t="$up_total" 'BEGIN {print t / 3}')"
echo "average: $(to_rates "$up_avg")"

echo
echo "Customers on H+ or LTE often see far less than these numbers. Compare on-site results with the phone reading."
