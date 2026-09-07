#!/usr/bin/env bash
set -euo pipefail

echo "== Configuring nftables firewall on Arch Linux =="

echo ">> Installing nftables..."
sudo pacman -S --noconfirm nftables

echo ">> Writing firewall configuration..."

sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;

        # Allow loopback traffic
        iifname "lo" accept

        # Drop invalid connection-tracking packets
        ct state invalid drop

        # Allow established and related connections
        ct state established,related accept

        # Allow all ICMPv4
        meta l4proto icmp accept

        # Allow all ICMPv6
        #
        # Required for proper IPv6 operation, including:
        # - Neighbor Discovery
        # - Router Advertisements
        # - Router Solicitations
        # - Neighbor Advertisements
        # - Path MTU Discovery
        # - ICMPv6 error messages
        meta l4proto icmpv6 accept
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

echo ">> Checking firewall syntax..."
sudo nft -c -f /etc/nftables.conf

echo ">> Enabling nftables..."
sudo systemctl enable nftables

echo ">> Applying firewall rules..."
sudo systemctl restart nftables

echo ">> Active nftables rules:"
sudo nft list ruleset

echo
echo "== Firewall configured successfully =="
