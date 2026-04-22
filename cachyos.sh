#!/bin/bash

# 1. High-Fidelity Audio Setup
echo "Optimizing Pipewire..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber

# 2. Razer Huntsman V3 Permissions
echo "Configuring Razer hardware rules..."
sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules <<EOF >/dev/null
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Optimization Complete!"
