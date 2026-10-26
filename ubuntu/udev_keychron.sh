#!/usr/bin/env bash
set -euo pipefail

if ! getent group plugdev > /dev/null; then
    sudo groupadd plugdev
fi

sudo usermod -aG plugdev "$USER"

sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3434", MODE="0660", GROUP="plugdev"
EOF

sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done! Log out and back in (or reboot) so the group change takes effect."
