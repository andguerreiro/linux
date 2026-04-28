#!/bin/bash

# 1. Download the official Google Chrome (.deb)
echo "--- Downloading Google Chrome ---"
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/google-chrome.deb
echo "Download finished."

# 2. Install Chrome using apt
echo "--- Installing Google Chrome ---"
sudo apt update
sudo apt install -y /tmp/google-chrome.deb
echo "Google Chrome installation complete."

# 3. Create Udev rule for Razer Huntsman V3
echo "--- Configuring hardware permissions (udev) ---"
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
# Razer Huntsman V3 - WebHID Access
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", TAG+="uaccess"
EOF'
echo "Udev rules created for Razer hardware."

# 4. Reload system rules and trigger changes
echo "--- Applying new hardware rules ---"
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "Hardware rules reloaded and triggered."

# 5. Cleanup temporary files
echo "--- Cleaning up ---"
rm /tmp/google-chrome.deb
echo "Temporary installation files removed."

echo "-----------------------"
echo "--- SETUP COMPLETE ---"
echo "Tip: Make sure to restart Chrome if it was already open."
