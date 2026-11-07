# OP VPS Optimizer

**Maintainer:** [OfficialOnePesewa](https://github.com/OfficialOnePesewa)

A conservative network-tuning toolkit for Debian and Ubuntu VPS servers.

## Features

- Detects supported Debian/Ubuntu systems.
- Enables TCP BBR when the running kernel supports it.
- Uses the FQ queueing discipline when supported.
- Applies moderate TCP buffer and network backlog settings.
- Keeps its configuration in a separate sysctl file.
- Includes status and rollback commands.
- Offers optional BadVPN-UDPGW installation.

## Supported systems

- Debian 11, 12 and 13
- Ubuntu 20.04, 22.04, 24.04 and later
- systemd-based VPS environments

Some VPS containers do not allow kernel-level network changes. In those environments, certain settings may not be available.

## Installation

Run this command as root or with sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/op-vps-optimizer/main/install.sh | sudo bash
