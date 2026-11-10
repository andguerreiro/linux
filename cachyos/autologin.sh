#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/sddm.conf.d/autologin.conf"

sudo mkdir -p /etc/sddm.conf.d

sudo tee "$CONFIG" > /dev/null <<'EOF'
[Autologin]
User=and
Session=niri.desktop
Relogin=false
EOF

echo "Created $CONFIG"
