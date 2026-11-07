OP VPS Optimizer

Maintainer: "OfficialOnePesewa" (https://github.com/OfficialOnePesewa)

A network optimization toolkit for Debian and Ubuntu VPS servers.

Features

- TCP BBR detection and configuration when supported.
- FQ queueing discipline detection.
- TCP buffer tuning.
- Network backlog optimization.
- Automatic dependency installation.
- Automatic executable permission configuration.
- Status and rollback commands.
- Optional BadVPN-UDPGW installation.

Supported Systems

- Debian 11, 12 and 13
- Ubuntu 20.04, 22.04, 24.04 and later
- x86_64 and other supported architectures

Installation

One-Line Automatic Installation

Log in as root and execute:

apt-get update && apt-get install -y curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | bash

This command automatically:

1. Updates the package index.
2. Installs curl and CA certificates if needed.
3. Downloads the OP VPS Optimizer installer.
4. Downloads and extracts the repository.
5. Installs the project files.
6. Sets executable permissions automatically.
7. Applies supported network optimizations.

No manual curl installation, sudo, or chmod commands are required.

The installer itself also checks for missing download dependencies when run directly.

Available Commands

Apply optimization:

op-vps-optimizer apply

Check VPS settings:

op-vps-optimizer status

Restore the previous optimizer configuration:

op-vps-optimizer rollback

Install optional BadVPN-UDPGW:

op-vps-optimizer install-badvpn

BadVPN-UDPGW

BadVPN-UDPGW is an optional UDP relay for compatible clients.

Default listening address:

127.0.0.1:7300

The default loopback binding avoids exposing an unauthenticated UDP relay publicly.

Upstream project:

https://github.com/ambrop72/badvpn

The upstream project is archived and unmaintained. Review its source and license before installation.

Network Settings

The optimizer manages:

/etc/sysctl.d/99-op-vps-optimizer.conf

Settings include:

- TCP congestion control when supported.
- FQ packet scheduling when supported.
- TCP receive and send buffers.
- Network backlog.
- TCP slow-start behavior.
- TCP MTU probing.

The optimizer does not modify firewall rules, SSH settings, IP forwarding, or reboot the VPS.

Rollback

Run:

op-vps-optimizer rollback

This removes the optimizer's managed configuration and restores the latest saved backup when available.

Important Notice

Network optimization cannot guarantee zero latency, eliminate buffering, or exceed your VPS provider's available bandwidth.

Results depend on server resources, network routing, congestion, packet loss, client connection quality, and destination servers.

Test changes before using them in production.

License

This project is licensed under the MIT License.

BadVPN is a separate upstream project and retains its own license and copyright notices.
