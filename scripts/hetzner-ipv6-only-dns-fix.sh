#!/usr/bin/env bash

set -euxo pipefail
export LC_ALL=C

DNS64_ADDRESSES=(
    # Kasper Dupont's Public NAT64 service: https://nat64.net
    2a01:4f9:c010:3f02::1
    2a00:1098:2c::1
    2a00:1098:2b::1
)

# Don't use Hetzner's default DNS servers.
if [ -f /etc/systemd/resolved.conf.d/hetzner.conf ]; then
    mv /etc/systemd/resolved.conf.d/hetzner.conf{,.bak}
fi

mkdir -p /etc/systemd/resolved.conf.d
cat <<EOF > /etc/systemd/resolved.conf.d/dns64.conf
[Resolve]
DNS=${DNS64_ADDRESSES[*]}
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
EOF

systemctl daemon-reload
systemctl restart systemd-resolved.service
systemctl restart systemd-networkd.service

# Fixup for Nix install -- the installer needs sudo.
apt install -y sudo
