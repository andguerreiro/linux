#!/usr/bin/env bash
set -euo pipefail

# --- Chromium (RPM from Fedora repos) ---
if ! rpm -q chromium > /dev/null 2>&1; then
    sudo dnf install -y chromium
fi

# --- udev rule for Keychron (vendor ID 3434) ---
# Fedora doesn't use a "plugdev" group; TAG+="uaccess" gives the
# currently logged-in user access automatically, so no group change is needed.
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done! Unplug and replug your Keychron keyboard (or reboot), then open"
echo "https://launcher.keychron.com in Chromium: chromium-browser"
