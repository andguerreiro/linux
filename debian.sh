#!/bin/bash
set -e

echo "=== Debian 13.3 post-install script ==="

if [ "$EUID" -eq 0 ]; then
  echo "Please run as a normal user (sudo will be used when needed)."
  exit 1
fi

echo ">>> Updating package index"
sudo apt update

# GRUB: set timeout to 0
echo ">>> Configuring GRUB timeout"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
if ! grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
  echo "GRUB_TIMEOUT=0" | sudo tee -a /etc/default/grub
fi
sudo update-grub

# Firewall (UFW)
echo ">>> Installing and configuring UFW"
sudo apt install -y ufw
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# Disable Bluetooth
echo ">>> Disabling Bluetooth service"
sudo systemctl disable --now bluetooth.service || true

# Repositories (Enable contrib, non-free and non-free-firmware)
echo ">>> Enabling contrib, non-free and non-free-firmware repositories"
sudo sed -i 's/main$/main contrib non-free non-free-firmware/' /etc/apt/sources.list
sudo apt update

# Install Nvidia Drivers and Headers
echo ">>> Installing Nvidia proprietary drivers"
sudo apt install -y linux-headers-amd64 nvidia-driver firmware-misc-nonfree

# Install software
echo ">>> Installing software"
sudo apt install -y mpv qbittorrent gimp curl gnupg2

# MPV with NVIDIA GPU
echo ">>> Configuring MPV with NVIDIA GPU"
mkdir -p ~/.config/mpv/
cat <<EOF > ~/.config/mpv/mpv.conf
vo=gpu
gpu-api=opengl
hwdec=nvdec
profile=gpu-hq
scale=ewa_hanning
cscale=ewa_hanning
video-sync=display-resample
interpolation
tscale=oversample
EOF

# Purge unwanted GNOME software
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
  totem \
  im-config \
  evolution \
  rhythmbox \
  shotwell \
  yelp \
  simple-scan \
  gnome-snapshot || true

sudo apt autoremove -y

# Install Spotify
echo ">>> Installing Spotify"
curl -sS https://download.spotify.com/debian/pubkey_C85661D953FF3D1F.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/spotify-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
sudo apt update
sudo apt install -y spotify-client

# GNOME customization
echo ">>> Applying GNOME settings"
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

# PipeWire bit-perfect audio
echo ">>> Configuring PipeWire bit-perfect rates"
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf << 'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber

echo "=== All tasks completed ==="
echo ">>> Reboot is strongly recommended to load the Nvidia driver."
