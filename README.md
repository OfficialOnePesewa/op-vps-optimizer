
# OP-VPS Optimizer
### VoIP & Gaming Edition
**Author:** OfficialOnePesewa

A Debian/Ubuntu VPS network optimizer with optional BadVPN UDP Gateway (UDPGW), diagnostics, safe network tuning, and rollback.

Repository:
https://github.com/OfficialOnePesewa/op-vps-optimizer

## Features

- Debian and Ubuntu support
- BBR availability detection for TCP traffic
- UDP socket buffer tuning
- IP forwarding
- BadVPN UDPGW built from upstream source
- systemd-managed UDPGW service
- VoIP, gaming and packet-drop diagnostics
- Backup and rollback of optimizer settings
- No automatic reboot
- No changes to ZIVPN credentials or user database

## Requirements

- Root access
- Ubuntu 20.04+ or Debian 11+
- Internet access
- Supported CPU architecture and sufficient disk space

## Install

Review the installer before running it on a production server:

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/scripts/install.sh -o /tmp/op-install.sh
less /tmp/op-install.sh
sudo bash /tmp/op-install.sh
```

Quick install:

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/scripts/install.sh | sudo bash
```

## Commands

```bash
sudo opvps optimize
sudo opvps diagnose
sudo opvps badvpn
sudo opvps rollback
sudo opvps help
```

## BadVPN UDPGW

The optional gateway listens on:

`127.0.0.1:7300`

This is suitable when a compatible tunneling service runs on the same VPS and can forward UDP traffic through UDPGW.

The listener is not public by default. Configure the client and tunnel application to use it where supported.

## VoIP and gaming

UDPGW is not a SIP server, RTP server, game server, or general-purpose UDP port forwarder. It only helps applications that support the BadVPN UDPGW protocol.

For native VoIP or games, verify that the required UDP traffic is actually routed through your tunnel. Do not expose UDPGW publicly without a deliberate security design.

## Diagnostics

```bash
sudo opvps diagnose
sudo journalctl -u badvpn-udpgw -n 50 --no-pager
sudo ss -lunp
```

Compare packet drops, jitter, latency under load, CPU usage, and real call/game performance before and after changes.

## Limitations

No optimizer can guarantee zero lag, no buffering, or maximum speed. Mobile coverage, carrier congestion, route quality, packet loss, server CPU, and application configuration all matter.

TCP BBR does not directly control Hysteria's QUIC congestion algorithm.

## License

MIT

