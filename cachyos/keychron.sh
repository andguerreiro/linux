#!/bin/bash
set -euo pipefail

sudo tee /etc/udev/rules.d/99-keychron.rules <<EOF
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
EOF

sudo tee /etc/udev/rules.d/90-keychron-link.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Done!"
