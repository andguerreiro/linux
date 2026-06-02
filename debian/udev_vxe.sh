#!/usr/bin/env bash
set -euo pipefail

getent group plugdev >/dev/null || sudo groupadd plugdev
sudo usermod -aG plugdev "$USER"

sudo tee /etc/udev/rules.d/99-vxe-webhid.rules >/dev/null <<'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="3554", MODE="0660", GROUP="plugdev"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
