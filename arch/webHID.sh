#!/bin/bash
set -euo pipefail
sudo tee /etc/udev/rules.d/99-gaming.rules <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Done!"
