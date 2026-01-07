#!/bin/bash

echo "🚀 Starting post-install setup..."

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

# 5. Mouse: Disable Acceleration
gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'
gsettings set org.gnome.desktop.peripherals.mouse speed 0

# 6. Power: Disable Sleep and Hibernation
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# 7. Keyboard: Compose Key and Custom Shortcuts
gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt']"

# 8. Audio: Pipewire Bit-perfect
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

# 9. Install Software
sudo apt install -y mpv qbittorrent libreoffice-calc libreoffice-gnome
sudo snap install spotify

echo "✅ Setup complete! Please reboot for all changes to take effect."
