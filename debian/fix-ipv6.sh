#!/bin/bash
set -euo pipefail

CONNECTION="AP124-5G"
SYSCTL_FILE="/etc/sysctl.d/99-ipv6.conf"

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo: sudo $0"
    exit 1
fi

echo "==> Installing required packages..."
apt-get update
apt-get install -y procps network-manager curl

echo "==> Starting NetworkManager..."
systemctl enable --now NetworkManager

# Check that the connection exists
if ! nmcli -t -f NAME connection show | grep -Fxq "$CONNECTION"; then
    echo "ERROR: NetworkManager connection '$CONNECTION' was not found."
    echo
    echo "Available connections:"
    nmcli -t -f NAME,TYPE connection show
    exit 1
fi

echo "==> Detecting Wi-Fi interface..."

# Get the device currently associated with this connection
IFACE=$(nmcli -g GENERAL.DEVICES connection show "$CONNECTION" 2>/dev/null \
    | head -n1 \
    | tr ',' '\n' \
    | awk 'NF && $1 != "--" {print $1; exit}')

# If the connection isn't currently active, find the first Wi-Fi device
if [ -z "${IFACE:-}" ] || [ "$IFACE" = "--" ]; then
    IFACE=$(nmcli -t -f DEVICE,TYPE device status \
        | awk -F: '$2 == "wifi" && $1 != "" {print $1; exit}')
fi

if [ -z "${IFACE:-}" ]; then
    echo "ERROR: Could not find a Wi-Fi interface."
    nmcli device status
    exit 1
fi

echo "Using interface: $IFACE"

echo "==> Configuring IPv6 sysctl settings..."

cat > "$SYSCTL_FILE" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 1
net.ipv6.conf.default.accept_ra = 1
EOF

sysctl --system >/dev/null

# Enable IPv6 and Router Advertisements on the actual interface
sysctl -w "net.ipv6.conf.${IFACE}.disable_ipv6=0" >/dev/null
sysctl -w "net.ipv6.conf.${IFACE}.accept_ra=1" >/dev/null

echo "==> Configuring NetworkManager connection..."

nmcli connection modify "$CONNECTION" \
    ipv6.method auto \
    ipv6.never-default no \
    ipv6.ignore-auto-routes no \
    ipv6.ignore-auto-dns no

echo "==> Reconnecting '$CONNECTION'..."

nmcli connection down "$CONNECTION" 2>/dev/null || true
sleep 2
nmcli connection up "$CONNECTION"

echo "==> Waiting for IPv6 configuration..."
sleep 5

echo
echo "========== IPv6 addresses =========="
ip -6 addr show dev "$IFACE" scope global || true

echo
echo "========== IPv6 default routes =========="
ip -6 route show default || true

echo
echo "========== IPv6 connectivity test =========="

if curl -6 -I --connect-timeout 10 https://prosettings.net/; then
    echo
    echo "IPv6 connectivity test: SUCCESS"
else
    echo
    echo "IPv6 connectivity test: FAILED"
    echo
    echo "Debug information:"
    echo "--- NetworkManager device status ---"
    nmcli device status
    echo
    echo "--- Connection IPv6 settings ---"
    nmcli connection show "$CONNECTION" | grep -E '^ipv6\.'
    echo
    echo "--- IPv6 addresses ---"
    ip -6 addr show dev "$IFACE"
    echo
    echo "--- IPv6 routes ---"
    ip -6 route
    exit 1
fi
