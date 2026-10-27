if grep -qw bbr <<< "$AVAILABLE"; then
  cat > "$TMP" <<'EOF'
# OP-VPS Optimizer - supported TCP settings
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
fi
