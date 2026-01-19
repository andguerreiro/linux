#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "ERROR: Please run as root (use 'su -' then run the script)"
  exit 1
fi

echo "--- Starting Debian 13 Post-Install Script ---"

## 1. Configure Sudoer
TARGET_USER="and"
echo "[1/6] Adding $TARGET_USER to sudo group..."
usermod -aG sudo "$TARGET_USER" || echo "User $TARGET_USER not found, skipping..."

## 2. GRUB Configuration
echo "[2/6] Configuring GRUB timeout to 0..."
cp /etc/default/grub /etc/default/grub.bak
sed -i 's/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=0/' /etc/default/grub
update-grub

## 3. Firewall Setup
echo "[3/6] Installing and configuring UFW..."
apt update && apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw deny ssh
ufw --force enable

## 4. Disable Bluetooth
echo "[4/6] Disabling Bluetooth..."
systemctl disable bluetooth.service || true
systemctl stop bluetooth.service || true

## 5. NVIDIA Drivers & Repositories
echo "[5/6] Configuring repositories and installing NVIDIA drivers..."
# Robust replacement to add components regardless of trailing spaces
sed -i 's/main[[:space:]]*$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list

apt update
apt install -y linux-headers-amd64 nvidia-driver firmware-misc-nonfree

## 6. Install Spotify
echo "[6/6] Installing Spotify..."
apt install -y curl gnupg2
# Using the verified working command
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list

apt update && apt install -y spotify-client

echo ""
echo "--- All tasks completed successfully! ---"
echo "A system reboot is required for the NVIDIA drivers and GRUB changes to take effect."
echo "You can reboot whenever you are ready by typing: sudo reboot"
