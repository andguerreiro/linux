#!/bin/bash
set -e

########################################
# 1. Pacotes base (Wayland + Apps)
########################################

sudo pacman -S --needed --noconfirm \
    sway swaybg swayidle swaylock \
    waybar wofi grim slurp wl-clipboard \
    kitty firefox lf micro udiskie udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent gimp \
    htop wavemon lm_sensors \
    pipewire pipewire-pulse wireplumber \
    playerctl wget git nano zip unzip \
    spotify-launcher \
    nvidia nvidia-utils nvidia-settings \
    xdg-desktop-portal xdg-desktop-portal-wlr

########################################
# 2. Fontconfig
########################################

mkdir -p ~/.config/fontconfig

cat <<EOF > ~/.config/fontconfig/fonts.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias><family>serif</family><prefer><family>Noto Serif</family></prefer></alias>
  <alias><family>sans-serif</family><prefer><family>Inter</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>JetBrains Mono Nerd Font</family></prefer></alias>
</fontconfig>
EOF

fc-cache -fv

########################################
# 3. Kitty
########################################

mkdir -p ~/.config/kitty

cat <<EOF > ~/.config/kitty/kitty.conf
font_family JetBrainsMono Nerd Font
font_size 11.0
confirm_os_window_close 0
background_opacity 0.95
EOF

########################################
# 4. Waybar (nativo, simples)
########################################

mkdir -p ~/.config/waybar

cat <<'EOF' > ~/.config/waybar/config
{
  "layer": "top",
  "position": "bottom",
  "spacing": 15,

  "modules-left": [
    "cpu",
    "memory",
    "disk",
    "network",
    "pulseaudio"
  ],

  "modules-center": [
    "clock"
  ],

  "cpu": {
    "interval": 2,
    "format": "CPU: {usage}%"
  },

  "memory": {
    "interval": 2,
    "format": "RAM: {used:0.1f}G [{percentage}%]"
  },

  "disk": {
    "interval": 60,
    "path": "/",
    "format": "SSD: {used} [{percentage}%]"
  },

  "network": {
    "interval": 5,
    "format-wifi": "NET: {essid} [{signalStrength}%]",
    "format-ethernet": "NET: LAN",
    "format-disconnected": "NET: OFF"
  },

  "pulseaudio": {
    "format": "VOL: {volume}%",
    "format-muted": "VOL: MUTE"
  },

  "clock": {
    "interval": 1,
    "format": "{:%Y-%m-%d %H:%M}"
  }
}
EOF

########################################
# 5. Sway config
########################################

mkdir -p ~/.config/sway

cat <<'EOF' > ~/.config/sway/config
set $mod Mod4
font pango:Inter Medium 11

# NVIDIA workaround
setenv WLR_NO_HARDWARE_CURSORS 1

exec_always --no-startup-id dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
exec --no-startup-id udiskie
exec --no-startup-id waybar

# OUTPUT
# Configure after first login with:
# swaymsg -t get_outputs
# Example:
# output DP-0 mode 1920x1080@239.964Hz adaptive_sync off

# Input
input * {
    xkb_layout us
    xkb_options compose:ralt
}

input type:pointer {
    accel_profile flat
}

# Keybindings
bindsym $mod+Return exec kitty
bindsym $mod+b exec firefox
bindsym $mod+s exec spotify-launcher
bindsym $mod+l exec kitty -e lf
bindsym $mod+m exec kitty -e micro
bindsym $mod+d exec wofi --show drun
bindsym $mod+q kill

bindsym Print exec grim ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bindsym $mod+Print exec slurp | grim -g - ~/Pictures/$(date +%Y%m%d_%H%M%S).png

bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +1%
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -1%
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle

bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

# Workspaces
bindsym $mod+1 workspace 1
bindsym $mod+2 workspace 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace 4
bindsym $mod+5 workspace 5
bindsym $mod+6 workspace 6
bindsym $mod+7 workspace 7
bindsym $mod+8 workspace 8
bindsym $mod+9 workspace 9
bindsym $mod+0 workspace 10

bindsym $mod+Shift+1 move container to workspace 1
bindsym $mod+Shift+2 move container to workspace 2
bindsym $mod+Shift+3 move container to workspace 3
bindsym $mod+Shift+4 move container to workspace 4
bindsym $mod+Shift+5 move container to workspace 5
bindsym $mod+Shift+6 move container to workspace 6
bindsym $mod+Shift+7 move container to workspace 7
bindsym $mod+Shift+8 move container to workspace 8
bindsym $mod+Shift+9 move container to workspace 9
bindsym $mod+Shift+0 move container to workspace 10

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
EOF

########################################
# 6. PipeWire
########################################

systemctl --user enable --now pipewire pipewire-pulse wireplumber

mkdir -p ~/.config/pipewire/pipewire.conf.d

cat <<'EOF' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber

########################################
# 7. lf
########################################

mkdir -p ~/.config/lf

cat <<EOF > ~/.config/lf/lfrc
set drawbox true
set icons true
set preview true
map <delete> \$rm -rI \$fx
map <enter> \${{
    nano "\$f"
}}
map <esc> clear
EOF

########################################
echo "Sway setup completed. Reboot and wun: sway"
