#!/usr/bin/env bash
set -euo pipefail

# Debian Trixie (KDE Plasma) Post-Install Script
echo "== Starting Debian post-install cleanup & optimization =="

#---------------------------------------------------------
# 1. GRUB – Set timeout to 0 (Performance & Boot Speed)
#---------------------------------------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

#---------------------------------------------------------
# 2. Bluetooth – Disable Service
#---------------------------------------------------------
echo "[Bluetooth] Disabling bluetooth.service"
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

#---------------------------------------------------------
# 3. Razer Synapse Web Udev Rules
#---------------------------------------------------------
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF
udevadm control --reload-rules && udevadm trigger'

echo "== Post-install complete. A reboot is required. =="
