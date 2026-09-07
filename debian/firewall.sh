#!/usr/bin/env bash
set -euo pipefail

echo "== Configuring nftables firewall on Debian =="

echo ">> Updating package lists..."
sudo apt update

echo ">> Installing nftables..."
sudo apt install -y nftables

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

        # Drop invalid packets
        ct state invalid drop

        # Allow established and related connections
        ct state established,related accept

        # Allow ICMPv4
        meta l4proto icmp accept

        # Allow all ICMPv6
        # Required for proper IPv6 operation
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

echo ">> Validating nftables configuration..."
sudo nft -c -f /etc/nftables.conf

echo ">> Enabling nftables service..."
sudo systemctl enable nftables

echo ">> Applying firewall rules..."
sudo systemctl restart nftables

echo ">> Checking nftables service..."
sudo systemctl --no-pager --full status nftables

echo
echo ">> Active nftables rules:"
sudo nft list ruleset

echo
echo "== Firewall configured successfully =="
