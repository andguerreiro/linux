#!/bin/bash

# --- ROOT CHECK ---
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  echo "Please switch to root using 'su -' and try again."
  exit 1
fi

# Determine the actual user
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" == "root" ]; then
    echo "Please enter the regular username you want to add to sudoers:"
    read REAL_USER
fi

echo "--- Starting Post-Installation for Debian 13 (Trixie) ---"

# 1. Add Non-Free Repositories
echo "Configuring non-free and non-free-firmware repositories..."
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update

# 2. Install Sudo, Curl and GPG
echo "Installing essential tools (sudo, curl, gnupg)..."
apt install -y sudo curl gnupg
usermod -aG sudo "$REAL_USER"

# 3. Grub Timeout to Zero
echo "Setting GRUB Timeout to 0..."
sed -i 's/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=0/g' /etc/default/grub
update-grub

# 4. Firewall (UFW)
echo "Installing and enabling Firewall (UFW)..."
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# 5. Disable Bluetooth
echo "Disabling Bluetooth..."
systemctl disable bluetooth.service || true
systemctl mask bluetooth.service

# 6. Install NVIDIA Proprietary Driver (FIXED FOR NON-INTERACTIVE)
echo "Blacklisting Nouveau driver to prevent conflicts..."
cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

echo "Updating initramfs..."
update-initramfs -u

echo "Installing NVIDIA Drivers (Automated OK)..."
# O uso de DEBIAN_FRONTEND=noninteractive pula as mensagens de confirmação do driver
export DEBIAN_FRONTEND=noninteractive
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  nvidia-driver firmware-misc-nonfree nvidia-settings nvidia-xconfig

# 7. Install Spotify (Official Repository)
echo "Adding Spotify repository and installing..."
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list
apt update
apt install -y spotify-client

# 8. Configure PipeWire (Allowed Rates for Audiophiles)
echo "Configuring PipeWire allowed rates..."
mkdir -p /etc/pipewire/pipewire.conf.d/
cat <<EOF > /etc/pipewire/pipewire.conf.d/99-allowed-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
}
EOF

# 9. Finalization
echo "Cleaning up..."
apt autoremove -y && apt autoclean

echo "--- Process complete! ---"
echo "The system needs to reboot to apply the NVIDIA drivers and GRUB changes."
echo "Press any key to reboot or Ctrl+C to exit."
read -n 1
reboot
