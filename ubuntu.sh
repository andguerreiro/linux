#!/bin/bash

echo "Starting post-install setup..."

# 1. Update System
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
sudo snap refresh

# 2. Security: Enable UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# 3. Hardware: Disable Bluetooth
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service

# 4. GNOME Customization
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

# 5. Audio: Pipewire Bit-perfect
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

# 6. Install Software
sudo apt install -y mpv qbittorrent libreoffice-calc libreoffice-gnome
sudo snap install spotify gimp

# 7. MPV with NVIDIA GPU
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

echo "Setup complete! Please reboot for all changes to take effect."
