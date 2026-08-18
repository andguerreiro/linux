#!/bin/bash
set -euo pipefail

# ============================================================
# Debian desktop firewall setup using nftables
#
# Security model:
#   - Block unsolicited incoming traffic
#   - Allow outgoing traffic
#   - Allow established and related connections
#   - Allow required ICMP/ICMPv6 traffic
#   - Allow DHCPv4 replies
#   - Allow mDNS from the local network for Avahi/printer discovery
#   - Block packet forwarding
#
# The script automatically detects:
#   - The primary network interface
#   - The local IPv4 network
#
# This makes the script suitable for future Debian installations
# and different network interface names.
#
# Intended for a desktop computer that:
#   - Is primarily an Internet client
#   - Uses Avahi for local service discovery
#   - Uses CUPS/IPP for printing
#   - Does not provide network services to other computers
# ============================================================

set -euo pipefail

NFT_CONFIG="/etc/nftables.conf"
BACKUP_DIR="/etc/nftables-backup"

# ------------------------------------------------------------
# Require root privileges
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    echo "Example: sudo $0"
    exit 1
fi

# ------------------------------------------------------------
# Detect the primary network interface
#
# The interface associated with the default IPv4 route is used.
# If no IPv4 default route exists, the default IPv6 route is used.
# ------------------------------------------------------------

LAN_IFACE="$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5; exit}')"

if [[ -z "${LAN_IFACE}" ]]; then
    LAN_IFACE="$(ip -6 route show default 2>/dev/null | awk 'NR==1 {print $5; exit}')"
fi

if [[ -z "${LAN_IFACE}" ]]; then
    echo "ERROR: Could not detect the primary network interface."
    echo
    echo "Available interfaces:"
    ip -br link
    exit 1
fi

if ! ip link show "$LAN_IFACE" >/dev/null 2>&1; then
    echo "ERROR: Detected interface '$LAN_IFACE' does not exist."
    exit 1
fi

# ------------------------------------------------------------
# Detect the local IPv4 network
#
# Example:
#   192.168.15.0/24
#
# This is obtained from the connected kernel route rather than
# from the machine's IP address.
# ------------------------------------------------------------

LAN_IPV4_NET="$(
    ip -4 route show dev "$LAN_IFACE" proto kernel scope link 2>/dev/null |
    awk '$1 ~ /^[0-9]+\./ {print $1; exit}'
)"

# ------------------------------------------------------------
# Install nftables if necessary
# ------------------------------------------------------------

if ! command -v nft >/dev/null 2>&1; then
    echo "nftables is not installed."
    echo "Installing nftables..."

    apt-get update
    apt-get install -y nftables
fi

# ------------------------------------------------------------
# Create a backup of the existing nftables configuration
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

if [[ -f "$NFT_CONFIG" ]]; then
    BACKUP_FILE="$BACKUP_DIR/nftables.conf.$(date +%Y%m%d-%H%M%S)"
    cp -a "$NFT_CONFIG" "$BACKUP_FILE"

    echo "Existing nftables configuration backed up to:"
    echo "  $BACKUP_FILE"
fi

# ------------------------------------------------------------
# Display detected network information
# ------------------------------------------------------------

echo
echo "Detected network configuration:"
echo "  Interface: $LAN_IFACE"

if [[ -n "$LAN_IPV4_NET" ]]; then
    echo "  IPv4 network: $LAN_IPV4_NET"
else
    echo "  IPv4 network: none detected"
fi

echo

# ------------------------------------------------------------
# Build the nftables configuration
# ------------------------------------------------------------

cat > "$NFT_CONFIG" <<EOF
#!/usr/sbin/nft -f

# Flush the current ruleset before loading this configuration.
flush ruleset

table inet filter {

    chain input {
        type filter hook input priority filter;
        policy drop;

        # Always allow local loopback traffic.
        iifname "lo" accept

        # Allow packets belonging to connections initiated by this host.
        ct state established,related accept

        # Drop malformed or invalid connection-tracking states.
        ct state invalid drop

        # Allow IPv4 ICMP required for normal network operation.
        ip protocol icmp accept

        # Allow IPv6 ICMP required for normal IPv6 operation.
        # ICMPv6 is essential for Neighbor Discovery,
        # Router Advertisements and Path MTU Discovery.
        ip6 nexthdr icmpv6 accept

EOF

# ------------------------------------------------------------
# Add IPv4-specific rules when an IPv4 network was detected
# ------------------------------------------------------------

if [[ -n "$LAN_IPV4_NET" ]]; then

    cat >> "$NFT_CONFIG" <<EOF
        # Allow DHCPv4 server replies to the DHCP client.
        # This is required for obtaining and renewing an IPv4 address.
        iifname "$LAN_IFACE" \
            udp sport 67 udp dport 68 accept

        # Allow mDNS/Bonjour traffic from the local IPv4 network.
        # This is required for Avahi-based printer discovery.
        iifname "$LAN_IFACE" \
            ip saddr $LAN_IPV4_NET \
            udp dport 5353 accept

EOF

fi

# ------------------------------------------------------------
# Add IPv6 mDNS rule
# ------------------------------------------------------------

cat >> "$NFT_CONFIG" <<EOF
        # Allow IPv6 mDNS from link-local addresses only.
        # Avahi uses link-local IPv6 for local network discovery.
        iifname "$LAN_IFACE" \
            ip6 saddr fe80::/10 \
            udp dport 5353 accept
    }

    chain forward {
        type filter hook forward priority filter;
        policy drop;
    }

    chain output {
        type filter hook output priority filter;
        policy accept;
    }
}
EOF

# ------------------------------------------------------------
# Validate the configuration before applying it
# ------------------------------------------------------------

echo "Validating nftables configuration..."

if ! nft -c -f "$NFT_CONFIG"; then
    echo
    echo "ERROR: nftables configuration validation failed."
    echo "The firewall was NOT changed."
    exit 1
fi

echo "Configuration syntax is valid."

# ------------------------------------------------------------
# Apply the new firewall rules
# ------------------------------------------------------------

echo
echo "Applying firewall rules..."

nft -f "$NFT_CONFIG"

# ------------------------------------------------------------
# Enable nftables at boot
# ------------------------------------------------------------

systemctl enable nftables.service
systemctl restart nftables.service

# ------------------------------------------------------------
# Display the resulting configuration
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Firewall successfully configured."
echo "============================================================"
echo
echo "Detected network interface:"
echo "  $LAN_IFACE"

if [[ -n "$LAN_IPV4_NET" ]]; then
    echo "Detected IPv4 network:"
    echo "  $LAN_IPV4_NET"
fi

echo
echo "Firewall policy:"
echo "  Incoming: BLOCKED by default"
echo "  Outgoing: ALLOWED"
echo "  Forwarding: BLOCKED"
echo
echo "Allowed local discovery:"
echo "  mDNS IPv4: UDP 5353"
echo "  mDNS IPv6: UDP 5353"
echo
echo "CUPS network ports are NOT opened."
echo "Local CUPS remains protected by its localhost binding."
echo
echo "Current nftables rules:"
echo

nft list ruleset

echo
echo "nftables service status:"
systemctl --no-pager --full status nftables.service || true

echo
echo "============================================================"
echo "Firewall setup complete."
echo "============================================================"
