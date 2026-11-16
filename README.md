# 🚀 OP VPS Optimizer · Streaming Edition v2.0.0

BBR congestion control and TCP/UDP tuning for smooth streaming, fast browsing, and quick downloads. Detects your VPS provider, OS and version. Works on Debian and Ubuntu.

## 📥 Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | sudo bash
```

## 🎛️ Commands

- `sudo op-optimize`: apply the optimization
- `sudo op-status`: show provider, OS, tuning and protected ports
- `sudo op-rollback`: undo everything

## 📝 Notes

- BBRv3 needs a kernel that ships it (for example XanMod). Stock kernels use BBR.
- Does not reboot the VPS. Does not touch ZIVPN, UDP Custom, BadVPN (7100/7200/7300), 3x-ui or Trojan.
- Backups are saved in `/var/backups/op-vps-optimizer/`.

## 👤 Author

**OfficialOnePesewa** · Telegram: [@OfficialOnePesewa](https://t.me/OfficialOnePesewa)
OP Data Solutions
