# OP VPS Optimizer - Streaming Edition

Network tuning for VPS servers that host ZIVPN UDP, UDP Custom and BadVPN UDPGW.
It targets smoother streaming, faster page opens, quicker downloads and fewer connection drops.

Made by [@OfficialOnePesewa](https://t.me/OfficialOnePesewa) · OP Data Solutions

---

## Quick install

Run this on your VPS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | sudo bash
```

No reboot is needed. Changes apply immediately.

---

## Supported systems

| Family | Distributions |
|---|---|
| Debian-based | Debian, Ubuntu, Linux Mint, Raspbian |
| RHEL-based | AlmaLinux, Rocky Linux, RHEL, CentOS, Oracle Linux, Amazon Linux |
| Other | Fedora, Arch Linux, openSUSE, Alpine Linux |

Works on KVM and most other VPS virtualization. OpenVZ and LXC hosts control the kernel,
so some settings may be refused. The installer skips those and applies the rest.

Alpine needs bash first: `apk add bash`

---

## Commands

After installation, these commands are available on the server:

| Command | What it does |
|---|---|
| `op-optimize` | Apply or re-apply the tuning |
| `op-status` | Show the active congestion control, buffers, watchdog state and VPN port status |
| `op-bench` | Measure download and upload speed |
| `op-ytcheck` | Time DNS, connect, TLS and first byte for YouTube hosts |
| `op-rollback` | Remove everything the optimizer added and restore the original values |

---

## What it changes

**Speed and streaming**
- BBR congestion control with the fq queue (falls back to cubic on older kernels)
- Larger socket buffers, sized by RAM, so fast downloads and uploads are not capped
- MTU probing and MSS clamping to prevent stalls on mobile links (3G, H+, 4G, LTE)
- TCP Fast Open and no slow-start restart after idle periods

**Connection stability**
- Longer firewall timeouts for established and UDP streams, so active sessions are not dropped during short pauses
- Keepalives that hold connections open through carrier NAT
- Auto-restart for the BadVPN UDPGW service if it crashes
- A watchdog that runs every minute: it restarts UDPGW if its ports go down and reapplies the tuning if the kernel values reset

**Protected services**

The optimizer never changes ZIVPN, UDP Custom or UDPGW configuration. It checks that ports
7100, 7200 and 7300 are listening after each run.

Files written:
- `/etc/sysctl.d/99-op-vps-optimizer.conf`
- `/etc/security/limits.d/99-op-vps-optimizer.conf`
- `/etc/systemd/system/op-watchdog.service` and `.timer`
- `/var/backups/op-vps-optimizer/original.env` (saved original values for rollback)

---

## Getting the best results

1. Check your VPS port speed. Your plan's bandwidth is the ceiling, and no script can exceed it.
2. Run `op-bench` and `op-ytcheck` before installing, then run them again after. Compare the numbers.
3. On customers' phones, set the VPN app to unrestricted battery use and remove it from any "sleeping apps" list.
4. Recommend a fast DNS (1.1.1.1 or 8.8.8.8) in the customer's app, if it has a DNS field.

Results depend on the VPS host, the route to the customer, and the customer's signal.
Tuning reduces stalls and drops. It cannot add bandwidth your plan or their network does not have.

---

## Uninstall

```bash
sudo op-rollback
```

This removes the sysctl and limits files, the MSS clamp rule, the watchdog timer and the UDPGW restart setting,
then restores the original congestion control and buffer values. A reboot restores every default.

---

## Repository layout

```
install.sh                  one-line bootstrap
scripts/common.sh          shared OS detection and helpers
scripts/optimize.sh        applies the tuning
scripts/status.sh          shows current state
scripts/bench.sh           speed test
scripts/yt-check.sh        YouTube open-time check
scripts/watchdog.sh        runs every minute, restarts UDPGW and reapplies tuning
scripts/rollback.sh        removes all changes
```

---

## Support

Telegram: [@OfficialOnePesewa](https://t.me/OfficialOnePesewa)

When asking for help, include the output of `op-status` and your OS name.

## License

MIT
