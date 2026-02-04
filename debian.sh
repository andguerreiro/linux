#!/usr/bin/env bash
set -euo pipefail

# Debian Trixie (Gnome) Post-Install Script
echo "== Starting Debian post-install cleanup & optimization =="

#---------------------------------------------------------
# 1. GRUB – Set timeout to 0
#---------------------------------------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo update-grub

#---------------------------------------------------------
# 2. Bluetooth – Disable Service
#---------------------------------------------------------
echo "[Bluetooth] Disabling bluetooth.service"
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

#---------------------------------------------------------
# 3. Purge unwanted GNOME packages
#---------------------------------------------------------
echo "[GNOME] Purging unwanted software"
TO_PURGE=(
    gnome-games gnome-characters gnome-clocks gnome-calendar 
    gnome-software gnome-software-common gnome-tweaks 
    gnome-color-manager gnome-contacts gnome-font-viewer gnome-logs 
    gnome-maps gnome-music gnome-sound-recorder gnome-weather 
    gnome-tour totem showtime im-config evolution rhythmbox 
    shotwell yelp simple-scan gnome-snapshot seahorse 
)

for pkg in "${TO_PURGE[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        sudo apt-get purge -y "$pkg"
    fi
done
sudo apt-get autoremove -y

#---------------------------------------------------------
# 4. GNOME - Input & Power Settings (Gsettings)
#---------------------------------------------------------
echo "[GSETTINGS] Applying user session tweaks"

if command -v gsettings &>/dev/null; then
    # Mouse: Flat profile
    gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'
    gsettings set org.gnome.desktop.peripherals.mouse speed 0.0

    # Keyboard: Set Right Alt as Compose Key
    gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt']"

    # Power & Sleep
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'

    # Notification & Audio tweaks
    gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

    #---------------------------------------------------------
    # 4.1 Custom Keyboard Shortcuts (Dconf)
    #---------------------------------------------------------
    echo "[GNOME] Injecting custom keyboard shortcuts"
    
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/']"

    dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ <<EOF
[custom0]
binding='<Control><Alt>t'
command='gnome-terminal'
name='terminal'

[custom1]
binding='<Control><Alt>End'
command='systemctl poweroff'
name='poweroff'

[custom2]
binding='<Control><Alt>Home'
command='systemctl reboot'
name='reboot'
EOF
fi

# System-level Power Button override
echo "[Power] Configuring logind to ignore power button"
sudo mkdir -p /etc/systemd/logind.conf.d
echo -e "[Login]\nHandlePowerKey=ignore" | sudo tee /etc/systemd/logind.conf.d/ignore-power-button.conf > /dev/null

#---------------------------------------------------------
# 5. Monitor – Persistent DP-3 configuration (239.964Hz)
#---------------------------------------------------------
echo "[Monitor] Applying ZOWIE XL LCD @ 239.964Hz on DP-3"
MONITORS_CONF="$HOME/.config/monitors.xml"
mkdir -p "$(dirname "$MONITORS_CONF")"

cat > "$MONITORS_CONF" <<EOF
<monitors version="2">
  <configuration>
    <layoutmode>logical</layoutmode>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>1</scale>
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>DP-3</connector>
          <vendor>BNQ</vendor>
          <product>ZOWIE XL LCD</product>
          <serial>EB28P01394SL0</serial>
        </monitorspec>
        <mode>
          <width>1920</width>
          <height>1080</height>
          <rate>239.964</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF

#---------------------------------------------------------
# 6. PipeWire – High-Fidelity Audio
#---------------------------------------------------------
echo "[PipeWire] Configuring bit-perfect sample rates"
PW_CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PW_CONF_DIR"

cat > "$PW_CONF_DIR/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

# Restart PipeWire services
systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

#---------------------------------------------------------
# Finalize
#---------------------------------------------------------
sudo apt-get update
echo "== Post-install complete. A reboot is required. =="
