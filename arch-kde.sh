#!/bin/bash

# --- Systemd-boot Configuration ---
# Sets the boot menu timeout to 0 for a faster boot
echo "Setting loader timeout to 0..."
sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

# --- UDEV Rules (Razer Huntsman V3) ---
# Grants necessary permissions for the Razer keyboard to the wheel group
echo "Configuring UDEV rules for Razer Huntsman V3..."
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF'
sudo udevadm control --reload-rules && sudo udevadm trigger

# --- Audio Configuration (Pipewire Custom Rates) ---
# Sets allowed sample rates for high-fidelity audio output
echo "Configuring Pipewire allowed-rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
printf "context.properties = {\n    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]\n}\n" > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber

echo "Done!"

