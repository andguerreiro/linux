#!/bin/bash
set -e

CONNECTION="AP124-5G"
SYSCTL_FILE="/etc/sysctl.d/99-ipv6.conf"

[ "$EUID" -eq 0 ] || { echo "Run with sudo."; exit 1; }

apt-get update
apt-get install -y procps network-manager curl

systemctl enable --now NetworkManager

IFACE=$(nmcli -g GENERAL.DEVICES connection show "$CONNECTION" 2>/dev/null | head -n1)

[ -n "$IFACE" ] && [ "$IFACE" != "--" ] ||
IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')

cat > "$SYSCTL_FILE" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 1
net.ipv6.conf.default.accept_ra = 1
EOF

sysctl --system >/dev/null
sysctl -w "net.ipv6.conf.$IFACE.disable_ipv6=0" >/dev/null
sysctl -w "net.ipv6.conf.$IFACE.accept_ra=1" >/dev/null

nmcli connection modify "$CONNECTION"
ipv6.method auto
ipv6.never-default no
ipv6.ignore-auto-routes no
ipv6.ignore-auto-dns no

nmcli connection down "$CONNECTION" 2>/dev/null || true
sleep 2
nmcli connection up "$CONNECTION"

sleep 5

ip -6 addr show dev "$IFACE" scope global
ip -6 route show default

curl -6 -I --connect-timeout 10 https://prosettings.net/
