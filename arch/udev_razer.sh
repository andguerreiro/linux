#!/bin/bash
set -euo pipefail

sudo tee /etc/udev/rules.d/99-razer.rules <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Done!"
