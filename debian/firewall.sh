#!/usr/bin/env bash
set -e

echo "== Configuring firewall =="

sudo apt install -y nftables

sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;

        iif lo accept
        ct state established,related accept
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

sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.conf

echo
echo "=== FIREWALL CONFIGURED ==="
echo "Incoming connections: BLOCKED"
echo "Outgoing connections: ALLOWED"
echo
