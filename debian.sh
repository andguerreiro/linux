#!/bin/bash
set -e

echo "=== Debian 13.3 post-install script ==="

# Ensure script is not run as root directly
if [ "$EUID" -eq 0 ]; then
  echo "Please run as a normal user (sudo will be used when needed)."
  exit 1
fi

echo ">>> Updating package index"
sudo apt update

#################################
# GRUB: set timeout to 0
#################################
echo ">>> Configuring GRUB timeout"

sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub

# If GRUB_TIMEOUT does not exist, add it
if ! grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
  echo "GRUB_TIMEOUT=0" | sudo tee -a /etc/default/grub
fi

sudo update-grub

#################################
# Firewall (UFW)
#################################
echo ">>> Installing and configuring UFW"

sudo apt install -y ufw
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw deny ssh
sudo ufw --force enable

#################################
# Disable Bluetooth
#################################
echo ">>> Disabling Bluetooth service"

sudo systemctl disable --now bluetooth.service || true

#################################
# Install software
#################################
echo ">>> Installing software"

sudo apt install -y mpv qbittorrent gimp

#################################
# Purge unwanted GNOME software
#################################
echo ">>> Purging GNOME packages"

sudo apt purge -y \
  gnome-games \
  gnome-characters \
  gnome-clocks \
  gnome-calendar \
  gnome-color-manager \
  gnome-contacts \
  gnome-font-viewer \
  gnome-logs \
  gnome-maps \
  gnome-music \
  gnome-sound-recorder \
  gnome-weather \
  gnome-shell-extension-prefs \
  totem \
  im-config \
  evolution \
  rhythmbox \
  shotwell \
  yelp \
  simple-scan \
  gnome-snapshot || true

sudo apt autoremove -y

#################################
# Install Spotify
#################################
echo ">>> Installing Spotify"

sudo apt install -y curl gnupg2

curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg \
  | sudo gpg --dearmor --yes \
  -o /usr/share/keyrings/spotify-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" \
  | sudo tee /etc/apt/sources.list.d/spotify.list

sudo apt update
sudo apt install -y spotify-client

#################################
# GNOME customization
#################################
echo ">>> Applying GNOME settings"

gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

#################################
# PipeWire bit-perfect audio
#################################
echo ">>> Configuring PipeWire bit-perfect rates"

mkdir -p ~/.config/pipewire/pipewire.conf.d/

cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf << 'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire

#################################
# Nvidia proprietary driver
#################################
echo ">>> Installing Nvidia proprietary drivers"

sudo apt install -y linux-headers-amd64

# Enable contrib and non-free if missing
if ! grep -E "contrib|non-free" /etc/apt/sources.list > /dev/null; then
  echo ">>> Enabling contrib and non-free repositories"
  sudo sed -i 's/main$/main contrib non-free/' /etc/apt/sources.list
fi

sudo apt update
sudo apt install -y nvidia-driver firmware-misc-nonfree

#################################
# Done
#################################
echo "=== All tasks completed ==="
echo ">>> Reboot is strongly recommended."
