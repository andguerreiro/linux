#!/bin/bash

# --- ROOT CHECK ---
# Ensures the script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# --- ENVIRONMENT VARIABLES ---
# Disables interactive prompts for the entire session
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a # Automates restart of services if 'needrestart' is installed

# --- WAIT FOR APT LOCK ---
# Prevents failure if automatic updates are running in the background
echo "Checking for system update locks..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
    echo "The system is currently running an automatic update. Waiting 5 seconds..."
    sleep 5
done

# Determine the actual user to add to the sudo group
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" == "root" ]; then
    echo "Please enter the regular username you want to add to sudoers:"
    read REAL_USER
fi

echo "--- Starting Post-Installation for Debian 13 ---"

# 1. Add Non-Free Repositories
# Enables contrib, non-free, and non-free-firmware for drivers and proprietary software
echo "Configuring non-free and non-free-firmware repositories..."
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update

# 2. Install Sudo, Curl and GPG
echo "Installing essential tools (sudo, curl, gnupg)..."
apt install -y sudo curl gnupg
usermod -aG sudo "$REAL_USER"

# 3. Grub Timeout to Zero
# Sets the boot menu timeout to 0 for faster booting
echo "Setting GRUB Timeout to 0..."
sed -i 's/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=0/g' /etc/default/grub
/usr/sbin/update-grub

# 4. Firewall (UFW)
# Installs UFW and sets default security policies
echo "Installing and enabling Firewall (UFW)..."
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# 5. Disable Bluetooth
# Stops and prevents Bluetooth from starting to save resources
echo "Disabling Bluetooth..."
systemctl stop bluetooth.service || true
systemctl disable bluetooth.service || true
systemctl mask bluetooth.service || true

# 6. Install NVIDIA Proprietary Driver
# Prevents Nouveau conflict and installs the proprietary driver non-interactively
echo "Blacklisting Nouveau driver..."
cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

echo "Updating initramfs..."
/usr/sbin/update-initramfs -u

echo "Installing NVIDIA Drivers (This may take a while)..."
# Force-confold/confdef ensures existing configs aren't overwritten by prompts
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  nvidia-driver firmware-misc-nonfree nvidia-settings nvidia-xconfig

# 7. Install Spotify (Official Repository)
# Adds the official Spotify GPG key and repository
echo "Adding Spotify repository and installing..."
curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list
apt update
apt install -y spotify-client

# 8. Configure PipeWire (Allowed Rates for Audiophiles)
# Sets standard sample rates to avoid unwanted resampling
echo "Configuring PipeWire allowed rates..."
mkdir -p /etc/pipewire/pipewire.conf.d/
cat <<EOF > /etc/pipewire/pipewire.conf.d/99-allowed-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
}
EOF

# 9. Finalization
# Cleans up unused packages and notifies the user
echo "Cleaning up package cache..."
apt autoremove -y
apt autoclean

echo ""
echo "--------------------------------------------------------"
echo "---               PROCESS COMPLETE!                  ---"
echo "--------------------------------------------------------"
echo "All configurations have been applied."
echo "IMPORTANT: You MUST reboot your computer to load the"
echo "NVIDIA driver and apply GRUB changes."
echo ""
echo "To reboot now, type: sudo reboot"
echo "--------------------------------------------------------"
