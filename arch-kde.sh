#!/bin/bash
set -e

echo "--- Starting System Configuration ---"

# 1. System Maintenance & Apps
echo "Installing packages..."
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw

# 2. Security (Firewall & Boot Permissions)
echo "Hardening system security..."
# Enable Firewall
sudo systemctl enable --now ufw.service
sudo ufw allow 631 >/dev/null
sudo ufw --force enable >/dev/null

# Fix 'World Accessible' /boot Security Hole
if grep -q "/boot" /etc/fstab; then
    echo "Securing /boot mount permissions..."
    sudo sed -i '/\/boot/ s/defaults/defaults,umask=0077,fmask=0077,dmask=0077/' /etc/etc/fstab
    sudo mount -o remount /boot || echo "Remount failed, will apply on next reboot."
    sudo chmod 700 /boot
    sudo bootctl random-seed
fi

# 3. Audio Optimization
echo "Configuring Pipewire rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat <<EOF > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber

# 4. Hardware & Boot Tweaks
echo "Applying hardware rules and boot timeout..."
# Hide boot menu timeout
[ -f /boot/loader/loader.conf ] && sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

# Razer Huntsman V3 Rules
sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo "--- All tweaks applied successfully! ---"
