#!/bin/bash
set -euo pipefail

echo "[Setup] Applying hardware udev rules..."

# 1532 = Razer | 3554 = VXE/ATK
sudo tee /etc/udev/rules.d/99-gaming-peripherals.rules > /dev/null <<EOF
# Razer Huntsman V3
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"

# VXE / ATK Mouse
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
EOF

# Reload and trigger once
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "[OK] All rules applied and triggered."
