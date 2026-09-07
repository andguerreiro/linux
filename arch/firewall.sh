#!/usr/bin/env bash
set -euo pipefail

echo "== Configuring nftables firewall on Arch Linux =="

echo ">> Installing nftables..."
sudo pacman -S --noconfirm nftables

echo ">> Creating firewall configuration..."

sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;

        # Allow loopback traffic
        iifname "lo" accept

        # Allow established and related connections
        ct state established,related accept

        # Allow ICMPv4
        meta l4proto icmp accept

        # Allow ICMPv6, including:
        # Neighbor Discovery, Router Advertisement,
        # Router Solicitation, and Path MTU Discovery
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

echo ">> Validating firewall configuration..."
sudo nft -c -f /etc/nftables.conf

echo ">> Enabling nftables service..."
sudo systemctl enable nftables

echo ">> Loading firewall rules..."
sudo systemctl restart nftables

echo ">> Checking nftables service status..."
sudo systemctl --no-pager --full status nftables

echo
echo ">> Active firewall rules:"
sudo nft list ruleset

echo
echo "== Firewall configured successfully with ICMPv6 support =="
