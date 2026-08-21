#!/usr/bin/env bash
set -euo pipefail

echo "== Configuring Arch Linux Firewall =="

echo ">> Installing nftables..."
sudo pacman -S --noconfirm nftables

echo ">> Enabling nftables..."
sudo systemctl enable --now nftables

echo ">> Configuring firewall..."

sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;

        iif "lo" accept
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
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

echo ">> Loading firewall rules..."
sudo nft -f /etc/nftables.conf

echo ">> Verifying firewall..."
sudo nft list ruleset

echo
echo "== Firewall configuration completed =="
