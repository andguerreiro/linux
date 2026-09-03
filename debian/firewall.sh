#!/usr/bin/env bash
set -e

echo "== Configuring firewall =="

sudo apt update
sudo apt install -y nftables

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
        ip protocol icmp accept

        # Allow essential ICMPv6 traffic
        ip6 nexthdr icmpv6 icmpv6 type {
            echo-request
            echo-reply
            destination-unreachable
            packet-too-big
            time-exceeded
            parameter-problem
            nd-router-solicit
            nd-router-advert
            nd-neighbor-solicit
            nd-neighbor-advert
            nd-redirect
        } accept
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

echo "== Validating nftables configuration =="

sudo nft -c -f /etc/nftables.conf

echo "== Enabling nftables service =="

sudo systemctl enable nftables
sudo systemctl restart nftables

echo "== Applying firewall rules =="

sudo nft -f /etc/nftables.conf

echo
echo "=== FIREWALL CONFIGURED ==="
echo "Incoming connections: BLOCKED (except essential ICMP/ICMPv6)"
echo "Outgoing connections: ALLOWED"
echo
echo "=== CURRENT NETWORK ADDRESSES ==="

ip addr
