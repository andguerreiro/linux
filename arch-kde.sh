#!/bin/bash
set -e

echo "--- Starting System Optimization ---"

# 1. Packages
echo "Installing apps..."
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw

# 2. Security (Firewall & /boot Lockdown)
echo "Hardening system..."
sudo systemctl enable --now ufw.service
sudo ufw allow 631 >/dev/null
sudo ufw --force enable >/dev/null

# Fix /boot permissions in fstab and live system
if grep -q '/boot' /etc/fstab; then
    # Replaces 'defaults' with strict masks; ensures only root can access
    sudo sed -i '/\/boot/ s/defaults/defaults,umask=0077,fmask=0077,dmask=0077/' /etc/fstab
    sudo mount -o remount /boot
    sudo chmod 700 /boot
    sudo bootctl random-seed
fi

# 3. Audio
echo "Configuring Pipewire..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat <<EOF > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber

# 4. Tweaks (Boot & Hardware)
echo "Applying final tweaks..."
[ -f /boot/loader/loader.conf ] && sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo "--- Done! /boot is now private and system is optimized. ---"
