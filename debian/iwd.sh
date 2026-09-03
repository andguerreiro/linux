#!/bin/bash
set -e

systemctl disable --now NetworkManager.service 2>/dev/null || true
systemctl mask NetworkManager.service 2>/dev/null || true

apt-get purge -y network-manager network-manager-gnome
apt-get autoremove -y

apt-get update
apt-get install -y iwd

systemctl enable --now iwd.service
systemctl enable --now systemd-networkd.service

mkdir -p /etc/systemd/network

cat > /etc/systemd/network/20-wifi.network <<'EOF'
[Match]
Type=wlan

[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF

systemctl restart systemd-networkd
