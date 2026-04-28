#!/usr/bin/env bash
set -euo pipefail

# Debian Trixie (Gnome) Post-Install Script
echo "== Starting Debian post-install cleanup & optimization =="

#---------------------------------------------------------
# 1. GRUB – Set timeout to 0 (Performance & Boot Speed)
#---------------------------------------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

#---------------------------------------------------------
# 2. Bluetooth – Disable Service
#---------------------------------------------------------
echo "[Bluetooth] Disabling bluetooth.service"
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

#---------------------------------------------------------
# 3. Purge unwanted GNOME packages (Fixed Logic)
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

sudo apt-get purge -y "${TO_PURGE[@]}" || echo "Some packages were not installed."

echo "[APT] Cleaning up dependencies..."
sudo apt-get autoremove -y
sudo apt-get autoclean

#---------------------------------------------------------
# 4. GNOME - Input & Power Settings (Gsettings)
#---------------------------------------------------------
echo "[GSETTINGS] Applying user session tweaks"

if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # Mouse: Flat profile (Essential for gaming/precision)
    gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'
    gsettings set org.gnome.desktop.peripherals.mouse speed 0.0

    # Keyboard & Power
    gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt']"
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

    # Shortcuts
    echo "[GNOME] Injecting custom keyboard shortcuts"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
      '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/']"

    # Terminal shortcut
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/name "'terminal'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command "'gnome-terminal'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/binding "'<Control><Alt>t'"

    # Poweroff shortcut
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/name "'poweroff'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/command "'systemctl poweroff'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/binding "'<Control><Alt>End'"

    # Reboot shortcut
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/name "'reboot'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/command "'systemctl reboot'"
    dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/binding "'<Control><Alt>Home'"
fi

#---------------------------------------------------------
# 5. System-level Power & Monitor
#---------------------------------------------------------
echo "[Power] Configuring logind to ignore power button"
sudo mkdir -p /etc/systemd/logind.conf.d
echo -e "[Login]\nHandlePowerKey=ignore" | sudo tee /etc/systemd/logind.conf.d/ignore-power-button.conf > /dev/null

echo "[Monitor] Applying ZOWIE XL LCD @ 239.964Hz"
mkdir -p "$HOME/.config"
cat > "$HOME/.config/monitors.xml" <<EOF
<monitors version="2">
  <configuration>
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
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat > "$HOME/.config/pipewire/pipewire.conf.d/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "== Post-install complete. A reboot is required. =="
