#!/bin/bash

# --- INITIAL CONFIGURATION ---
USER_NAME=$(whoami)
if [ "$USER_NAME" == "root" ]; then
    echo "Please enter your regular username to add it to sudoers:"
    read USER_NAME
fi

echo "--- Starting Post-Installation for Debian 13 ---"

# 1. Add Non-Free Repositories
echo "Configuring non-free and non-free-firmware repositories..."
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update

# 2. Install Sudo, Curl and GPG
echo "Installing essential tools (sudo, curl, gnupg)..."
apt install -y sudo curl gnupg
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

# 5. Disable Bluetooth
echo "Disabling Bluetooth..."
systemctl disable bluetooth.service
systemctl mask bluetooth.service

# 6. Install NVIDIA Proprietary Driver
echo "Installing NVIDIA Drivers and Firmware..."
apt install -y nvidia-driver firmware-misc-nonfree nvidia-settings nvidia-xconfig

# 7. Install Spotify (Official Repository)
echo "Adding Spotify repository and installing..."
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list
apt update
apt install -y spotify-client

# 8. Configure PipeWire (Allowed Rates for Audiophiles)
# This allows PipeWire to switch between 44.1kHz and 48kHz automatically
echo "Configuring PipeWire allowed rates..."
mkdir -p /etc/pipewire/pipewire.conf.d/
cat <<EOF > /etc/pipewire/pipewire.conf.d/99-allowed-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
}
EOF

# 9. Finalization
echo "--- Process complete! ---"
echo "The system needs to reboot to apply all changes."
echo "Press any key to reboot or Ctrl+C to exit."
read -n 1
reboot
