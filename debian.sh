#!/bin/bash

# --- ROOT CHECK ---
# Ensures the script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  echo "Try: su -c 'wget -qO- https://raw.githubusercontent.com/andguerreiro/linux/main/debian.sh | bash'"
  exit 1
fi

# --- USER DETECTION ---
# Primary user is 'and'. Fallback to SUDO_USER or logname if 'and' doesn't exist.
REAL_USER="and"
if ! id "$REAL_USER" >/dev/null 2>&1; then
    REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
    if [ -z "$REAL_USER" ] || [ "$REAL_USER" == "root" ]; then
        echo "User 'and' not found. Please enter your username:"
        read REAL_USER
    fi
fi

# --- ENVIRONMENT VARIABLES ---
# Disables interactive prompts and automates service restarts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a 

# --- WAIT FOR APT LOCK ---
echo "Checking for system update locks..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
    echo "The system is currently running an automatic update. Waiting 5 seconds..."
    sleep 5
done

echo "--- Starting Post-Installation for Debian 13 (Trixie) ---"

# 1. Add Non-Free Repositories
echo "Configuring contrib, non-free, and non-free-firmware repositories..."
sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
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
echo "Disabling Bluetooth services..."
systemctl disable --now bluetooth.service || true
systemctl mask bluetooth.service || true

# 6. Install NVIDIA Proprietary Driver
echo "Blacklisting Nouveau driver..."
cat <<EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

echo "Updating initramfs..."
update-initramfs -u

echo "Installing NVIDIA Drivers..."
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  nvidia-driver firmware-misc-nonfree nvidia-settings nvidia-xconfig

# 7. Install Spotify (Official Repository)
echo "Adding Spotify official repository..."
curl -sS https://download.spotify.com/debian/pubkey_6224F994118D76A3.gpg | gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list
apt update
apt install -y spotify-client

# 8. Configure PipeWire (Allowed Rates)
echo "Configuring PipeWire allowed rates..."
mkdir -p /etc/pipewire/pipewire.conf.d/
cat <<EOF > /etc/pipewire/pipewire.conf.d/99-allowed-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
}
EOF

# 9. Finalization
echo "Cleaning up package cache..."
apt autoremove -y
apt autoclean

echo ""
echo "--------------------------------------------------------"
echo "---               PROCESS COMPLETE!                  ---"
echo "--------------------------------------------------------"
echo "User '$REAL_USER' has been added to sudoers."
echo "IMPORTANT: REBOOT your computer to apply changes."
echo "--------------------------------------------------------"
