#!/bin/bash
set -euo pipefail

# Wi-Fi Power Management & Stability Fixes
echo "options mt76x2u disable_usb_lpm=1" | sudo tee /etc/modprobe.d/mt76x2u.conf
sudo mkdir -p /etc/NetworkManager/conf.d && echo -e "[connection]\nwifi.powersave = 2" | sudo tee /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf

echo "Done! Reboot recommended."
