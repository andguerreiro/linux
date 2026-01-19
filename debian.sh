#!/bin/bash

# --- INITIAL CONFIGURATION ---
# Replace 'your_user' with your actual username
USER_NAME=$(whoami)
if [ "$USER_NAME" == "root" ]; then
    echo "Please enter your regular username to add it to sudoers:"
    read USER_NAME
fi

echo "--- Starting Post-Installation for Debian 13 ---"

# 1. Add Non-Free Repositories (Required for RTX 4070)
echo "Configuring non-free and non-free-firmware repositories..."
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update

# 2. Install Sudo and add user to the group
echo "Configuring Sudo..."
apt install -y sudo
usermod -aG sudo $USER_NAME

# 3. Grub Timeout to Zero
echo "Setting GRUB Timeout to 0..."
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
update-grub

# 4. Firewall (UFW)
echo "Installing and enabling Firewall (UFW)..."
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw enable

# 5. Disable Bluetooth (Resource saving/security)
echo "Disabling Bluetooth..."
systemctl disable bluetooth.service
systemctl mask bluetooth.service

# 6. Install NVIDIA Proprietary Driver
# Debian 13 kernel handles the 4000 series well
echo "Installing NVIDIA Drivers and Firmware..."
apt install -y nvidia-driver firmware-misc-nonfree nvidia-settings nvidia-xconfig

# 7. Finalization
echo "--- Process complete! ---"
echo "The system needs to reboot to load drivers and apply sudo permissions."
echo "Press any key to reboot or Ctrl+C to exit."
read -n 1
reboot
