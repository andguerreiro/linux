#!/bin/bash

# Ubuntu Fresh Install Post-Setup Script
# --------------------------------------

echo "🚀 Starting post-install setup..."

# 1. Update System
echo "📦 Updating repositories and upgrading packages..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
sudo snap refresh

# 2. Security: Enable UFW
echo "🛡️ Configuring Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# 3. Hardware: Disable Bluetooth
echo "📡 Disabling Bluetooth service..."
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service

# 4. GNOME Customization: Notifications, Volume & Search
echo "⚙️ Tweaking GNOME settings..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.desktop.search-providers disable-external true
gsettings set org.gnome.desktop.search-providers disabled "['org.gnome.Contacts.desktop', 'org.gnome.Documents.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Calendar.desktop', 'org.gnome.Calculator.desktop', 'org.gnome.Characters.desktop', 'org.gnome.clocks.desktop', 'org.gnome.Software.desktop']"

# 5. Mouse: Disable Acceleration (Set to Flat Profile)
echo "🖱️ Disabling mouse acceleration (Flat Profile)..."
gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'
gsettings set org.gnome.desktop.peripherals.mouse speed 0

# 6. Power: Disable Screen Blank, Suspend, and Hibernation
echo "🔌 Disabling power saving (Screen Blank, Suspend, Hibernate)..."
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# 7. Keyboard: Enable Compose Key and Custom Shortcuts
echo "⌨️ Configuring Keyboard Shortcuts..."
# Enable Compose Key (Right Alt)
gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt']"

# Define Custom Shortcuts (Power Off & Reboot)
BEGIN_PATH="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
KEY_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Shortcut 1: Power Off (Ctrl+Alt+End)
gsettings set $BEGIN_PATH:$KEY_PATH/custom0/ name 'Power Off'
gsettings set $BEGIN_PATH:$KEY_PATH/custom0/ command 'poweroff'
gsettings set $BEGIN_PATH:$KEY_PATH/custom0/ binding '<Control><Alt>End'

# Shortcut 2: Reboot (Ctrl+Alt+Home)
gsettings set $BEGIN_PATH:$KEY_PATH/custom1/ name 'Reboot'
gsettings set $BEGIN_PATH:$KEY_PATH/custom1/ command 'reboot'
gsettings set $BEGIN_PATH:$KEY_PATH/custom1/ binding '<Control><Alt>Home'

# Apply the custom shortcuts list to GNOME
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$KEY_PATH/custom0/', '$KEY_PATH/custom1/']"

# 8. Audio: Pipewire Bit-perfect setup
echo "🎵 Configuring Pipewire for high-res audio..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

# 9. Install Software via APT
echo "📥 Installing APT packages..."
sudo apt install -y mpv qbittorrent libreoffice-calc libreoffice-gnome

# 10. Install Software via Snap
echo "📥 Installing Snap packages (Spotify)..."
sudo snap install spotify

echo "✅ Setup complete! Please reboot to finalize power and system changes."
