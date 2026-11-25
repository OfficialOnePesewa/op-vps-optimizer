#!/usr/bin/env bash
# OP VPS Optimizer - Streaming Edition: speed test
# Measures download and upload from this VPS to Cloudflare's public endpoints.
echo "== Download (3 runs, 100 MB each) =="
for i in 1 2 3; do
  curl -o /dev/null -s -w "run $i: %{speed_download} bytes/s\n" \
    "https://speed.cloudflare.com/__down?bytes=104857600" || echo "run $i: failed"
done

echo
echo "== Upload (3 runs, 20 MB each) =="
for i in 1 2 3; do
  head -c 20971520 /dev/urandom > /tmp/op-upload-test.bin
  curl -o /dev/null -s -w "run $i: %{speed_upload} bytes/s\n" \
    -X POST --data-binary @/tmp/op-upload-test.bin \
    "https://speed.cloudflare.com/__up" || echo "run $i: failed"
done
rm -f /tmp/op-upload-test.bin

echo
echo "Convert bytes/s to Mbps: multiply by 8, divide by 1,000,000."
echo "Convert bytes/s to MB/s: divide by 1,000,000."
