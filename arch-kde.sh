#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "---------------------------------------------------"
echo "1. Purging unwanted packages (Forced Purge)..."
echo "---------------------------------------------------"
# Added || true so it doesn't crash if packages are already removed
sudo pacman -Rdd --noconfirm qt6-tools v4l-utils hwloc vim discover 2>/dev/null || true

echo "---------------------------------------------------"
echo "2. Installing Applications and Utilities..."
echo "---------------------------------------------------"
sudo pacman -S --needed --noconfirm \
    dolphin konsole kate ark gwenview kcalc okular \
    unrar zip unzip \
    firefox chromium \
    ufw

echo "---------------------------------------------------"
echo "3. Configuring Firewall (UFW)..."
echo "---------------------------------------------------"
sudo systemctl enable --now ufw.service >/dev/null 2>&1
sudo ufw allow 631/tcp >/dev/null
sudo ufw allow 631/udp >/dev/null
# Enable without extra prompts
echo "y" | sudo ufw enable >/dev/null

echo "---------------------------------------------------"
echo "4. Optimizing Audio (Pipewire High-Res)..."
echo "---------------------------------------------------"
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat <<EOF > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF
# Restarting services to apply changes
systemctl --user restart pipewire pipewire-pulse wireplumber

echo "---------------------------------------------------"
echo "5. Configuring Bootloader (Systemd-boot)..."
echo "---------------------------------------------------"
if [ -f /boot/loader/loader.conf ]; then
    sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
    echo "Loader timeout set to 0."
else
    echo "Warning: /boot/loader/loader.conf not found. Skipping..."
fi

echo "---------------------------------------------------"
echo "6. Configuring UDEV Rules (Razer Huntsman V3)..."
echo "---------------------------------------------------"
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF'
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "---------------------------------------------------"
echo "Configuration completed successfully!"
echo "---------------------------------------------------"