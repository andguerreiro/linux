#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y nftables

sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;

        iifname "lo" accept

        ct state invalid drop
        ct state established,related accept

        ip protocol icmp accept

        meta l4proto ipv6-icmp icmpv6 type {
            echo-request,
            echo-reply,
            destination-unreachable,
            packet-too-big,
            time-exceeded,
            parameter-problem,
            nd-router-solicit,
            nd-router-advert,
            nd-neighbor-solicit,
            nd-neighbor-advert,
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

sudo nft -c -f /etc/nftables.conf
sudo systemctl enable nftables
sudo systemctl restart nftables

sudo nft list ruleset
