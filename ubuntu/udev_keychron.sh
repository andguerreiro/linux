#!/bin/bash
set -euo pipefail

sudo tee /etc/udev/rules.d/99-keychron.rules >/dev/null <<EOF
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0666", GROUP="sudo"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0666", GROUP="sudo"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger --action=add

echo "Done!"
