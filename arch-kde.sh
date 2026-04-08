#!/bin/bash

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

# --- Audio Configuration (Pipewire Custom Rates) ---
echo "Configuring Pipewire allowed-rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
printf "context.properties = {\n    default.clock.rate = 44100\n    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]\n}\n" > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
echo "Done: Pipewire configuration file written."

echo "Restarting Pipewire services..."
systemctl --user restart pipewire pipewire-pulse wireplumber
echo "Done: Pipewire, Pipewire-Pulse, and Wireplumber restarted."

echo "All Done! Your system configuration is complete."

