#!/usr/bin/env bash
set -euo pipefail

flatpak info org.chromium.Chromium >/dev/null

sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules >/dev/null <<'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="02b0", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="02b0", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

flatpak override --user --device=all org.chromium.Chromium
flatpak override --user --filesystem=/run/udev:ro org.chromium.Chromium
