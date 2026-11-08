# OP VPS Optimizer — Streaming Edition

**Maintainer:** [OfficialOnePesewa](https://github.com/OfficialOnePesewa) · Telegram: @OfficialOnePesewa

A network optimization toolkit for Debian and Ubuntu VPS servers, tuned for smoother streaming, browsing, downloads, calls and gaming over VPN.

---

## Quick Install

Log in to your VPS as **root**, then copy and run this one command:

```bash
apt-get update && apt-get install -y curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | bash
```

That's all. No `sudo` or `chmod` needed. The same command also updates an existing install to the latest version.

## Optional: Install BadVPN-UDPGW

```bash
op-vps-optimizer install-badvpn
```

## Check Everything Is Working

```bash
op-vps-optimizer status
```

Look for `[PASS]` next to BBR, FQ, TCP buffers and the interface boost service.

---

## Features

- TCP BBR and FQ detection, enabled when your VPS supports them
- Large TCP and UDP buffers for high-latency links (better for video streaming)
- Higher network queue and connection backlogs
- MTU probing and MSS clamping to reduce stalls inside VPN tunnels
- Connection tracking tuned for many UDP users
- Interface boost service that re-applies after every reboot
- Original kernel values saved on first run, so rollback is a true restore
- Streaming health check in `status`
- Optional BadVPN-UDPGW on ports 7100, 7200 and 7300
- Automatic dependency installation

## Supported Systems

- Debian 11, 12 and 13
- Ubuntu 20.04, 22.04, 24.04 and later
- x86_64 and other supported architectures

---

## Commands

| Command | What it does |
|---|---|
| `op-vps-optimizer apply` | Apply the streaming optimization |
| `op-vps-optimizer status` | Show settings and the streaming health check |
| `op-vps-optimizer rollback` | Restore your original settings and remove the optimizer service |
| `op-vps-optimizer rollback --full` | Same as rollback, and also remove the OP BadVPN-UDPGW services |
| `op-vps-optimizer install-badvpn` | Install or update BadVPN-UDPGW |
| `op-vps-optimizer help` | Show help |

---

## BadVPN-UDPGW

BadVPN-UDPGW is an optional UDP relay for compatible VPN clients (for example HTTP Custom).

| Port | Address |
|---|---|
| 7100 | 127.0.0.1:7100 |
| 7200 | 127.0.0.1:7200 |
| 7300 | 127.0.0.1:7300 (recommended default) |

In your VPN app, set UDPGW to `127.0.0.1:7300`.

- All ports bind to loopback only, so the relay is not exposed publicly.
- If a port is already used by another service, the installer leaves it alone and skips it.
- Upstream project: https://github.com/ambrop72/badvpn
- The upstream project is archived and unmaintained. Review its source and license before installing.

---

## What Gets Changed

| Item | Location |
|---|---|
| Kernel network settings | `/etc/sysctl.d/99-op-vps-optimizer.conf` |
| Interface boost service | `op-stream-boost.service` |
| Saved original values | `/var/backups/op-vps-optimizer/` |
| BadVPN-UDPGW (optional) | `op-badvpn-udpgw@7100`, `@7200`, `@7300` |

**Firewall:** the optimizer adds one rule to the `mangle` table (TCP MSS clamp) and removes it on rollback. It does not flush or change any other firewall rules.

The optimizer does not touch SSH settings or IP forwarding, does not stop your VPN services (ZIVPN, UDP Custom and others), and never reboots the VPS.

---

## Rollback

```bash
op-vps-optimizer rollback
```

Restores your original kernel values, removes the optimizer's configuration, interface boost service and MSS clamp rule. BadVPN-UDPGW keeps running unless you use `rollback --full`. No reboot is needed.

---

## Still Buffering?

Optimization can't beat your VPS or network limits. If video still stalls:

1. Run `op-vps-optimizer status` and check for `FAIL` or a CPU load warning.
2. A server closer to you gives lower latency than any tweak.
3. Try a lower MTU (for example 1400) in your VPN app.
4. Weak mobile signal (H+/3G) can't be fixed from the server.

## Important Notice

Network optimization cannot guarantee zero latency, eliminate buffering, or exceed your VPS provider's available bandwidth. Results depend on server resources, network routing, congestion, packet loss, client connection quality and destination servers. Test changes before using them in production.

## License

MIT License.

BadVPN is a separate upstream project and retains its own license and copyright notices.
