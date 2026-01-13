#!/bin/bash

# 1. Update the system
echo "Updating system packages..."
sudo dnf upgrade -y

# 2. Enable RPM Fusion Repositories (Required for Nvidia Drivers)
echo "Enabling RPM Fusion repositories..."
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 3. Install Nvidia Proprietary Drivers
echo "Installing Nvidia proprietary drivers and CUDA..."
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

# Wait for the driver module to build (important for new installs)
echo "Waiting for Nvidia kernel module to build... this may take a minute."
sleep 5

# 4. Configure Pipewire Allowed Rates
echo "Configuring Pipewire audio sample rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf

# Restart Pipewire services
systemctl --user restart pipewire

# 5. Finalize and Reboot
echo "Setup complete. System will reboot in 5 seconds..."
sleep 5
sudo reboot
