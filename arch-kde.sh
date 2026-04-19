#!/bin/bash

# --- Purge Specific Packages ---
echo "Purging unwanted packages (ignoring dependencies)..."
# Using -Rdd to force removal of packages required by Plasma/FFmpeg
sudo pacman -Rdd --noconfirm qt6-tools v4l-utils hwloc vim
echo "Done: Packages purged."

# --- Systemd-boot Configuration ---
echo "Setting loader timeout to 0..."
sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
echo "Done: Boot loader timeout set to 0."

# --- UDEV Rules (Razer Huntsman V3) ---
echo "Configuring UDEV rules for Razer Huntsman V3..."
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF'
echo "Done: UDEV rule file created."

echo "Applying UDEV rules..."
sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Done: UDEV rules reloaded and triggered."

echo "All Done! Your system configuration is complete."
