#!/usr/bin/env bash
set -euo pipefail

echo "=== Ubuntu Server 24.04 — i3 Workflow (REBUILT FROM SCRATCH) ==="

# --------------------------------------------------
# Helpers
# --------------------------------------------------
append_once() {
  local line="$1"
  local file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# --------------------------------------------------
# 0. Base system
# --------------------------------------------------
sudo apt update
sudo apt install -y \
  xorg xinit x11-xserver-utils x11-xkb-utils \
  i3 i3blocks dmenu dex kitty firefox \
  lf micro nano udiskie udisks2 \
  pipewire pipewire-audio pipewire-pulse wireplumber \
  lm-sensors htop nvtop wavemon wget curl git unzip zip \
  maim playerctl mpv qbittorrent gimp \
  fonts-jetbrains-mono fonts-inter fonts-noto \
  network-manager libinput-tools ca-certificates snapd

# --------------------------------------------------
# 1. NVIDIA
# --------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
  sudo ubuntu-drivers autoinstall
fi

# --------------------------------------------------
# 2. Spotify
# --------------------------------------------------
if ! snap list | grep -q "^spotify "; then
  sudo snap install spotify
fi

# --------------------------------------------------
# 3. Fonts & Kitty
# --------------------------------------------------
mkdir -p ~/.config/fontconfig ~/.config/kitty
cat <<EOF > ~/.config/fontconfig/fonts.conf
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>
  <alias><family>sans-serif</family><prefer><family>Inter</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>JetBrains Mono</family></prefer></alias>
</fontconfig>
EOF
fc-cache -fv

cat <<EOF > ~/.config/kitty/kitty.conf
font_family JetBrains Mono
font_size 11.0
confirm_os_window_close 0
background_opacity 0.95
EOF

# --------------------------------------------------
# 4. i3blocks (REBUILT VOLUME BLOCK)
# --------------------------------------------------
mkdir -p ~/.config/i3blocks

cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff

[cpu]
label=CPU:
command=sh -c 'TEMP=$(sensors 2>/dev/null | awk "/Package id 0/ {print int(\$4)}"); USAGE=$(top -bn1 | awk "/Cpu\\(s\\)/ {print int(100-\$8)}"); echo "${TEMP:-?}°C [${USAGE}%]"'
interval=2

[gpu]
label=GPU:
command=sh -c 'command -v nvidia-smi >/dev/null || { echo OFF; exit; }; nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk "{printf \"%d°C [%d%%]\\n\", \$1, \$2}" || echo OFF'
interval=2

[memory]
label=RAM:
command=free -m | awk '/Mem:/ {printf "%.1fG [%.0f%%]\n", $3/1024, ($3/$2)*100}'
interval=2

[disk]
label=SSD:
command=df -h --output=used,pcent / | tail -1 | awk '{printf "%s [%s]\n", $1, $2}'
interval=60

[wireless]
label=NET:
command=nmcli -t -f active,ssid dev wifi | grep "^yes" | cut -d: -f2 || echo OFF
interval=5

[volume]
label=VOL:
# This command pulls volume directly from PipeWire every 1 second. 
# No scripts, no signals, just pure command.
command=wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{if($3=="[MUTED]") print "MUTE"; else print int($2*100)"%"}'
interval=1

[time]
command=date '+%Y-%m-%d %H:%M'
interval=1
EOF

# --------------------------------------------------
# 5. i3 Config (FULL BINDS 1-10 + RESTART)
# --------------------------------------------------
mkdir -p ~/.config/i3

cat <<'EOF' > ~/.config/i3/config
set $mod Mod4
font pango:Inter Medium 11

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id setxkbmap -layout us -option compose:ralt
exec_always --no-startup-id xrandr --output DP-0 --mode 1920x1080 --rate 239.96
exec_always --no-startup-id xset s off -dpms
exec --no-startup-id udiskie &

floating_modifier $mod
tiling_drag modifier titlebar

# --- Simplest Volume Keys ---
bindsym XF86AudioRaiseVolume exec --no-startup-id wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute        exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

# --- Media Keys ---
bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

# --- Shortcuts ---
bindsym $mod+Return exec kitty
bindsym $mod+b exec firefox
bindsym $mod+s exec spotify
bindsym $mod+l exec kitty -e lf
bindsym $mod+m exec kitty -e micro
bindsym $mod+d exec dmenu_run
bindsym $mod+q kill

# --- Workspaces (1-10) ---
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10

bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10

# --- Focus/Move ---
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# --- Layout ---
bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

# --- Resize ---
mode "resize" {
    bindsym Left resize shrink width 10 px or 10 ppt
    bindsym Down resize grow height 10 px or 10 ppt
    bindsym Up resize shrink height 10 px or 10 ppt
    bindsym Right resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# --- SYSTEM (RESTART INCLUDED) ---
bindsym $mod+Shift+r restart
bindsym Control+Mod1+End exec poweroff
bindsym Control+Mod1+Home exec reboot

bar {
    font pango:JetBrains Mono 11
    status_command i3blocks
    position bottom
}
EOF

# --------------------------------------------------
# 6. Finalize (startx & PipeWire)
# --------------------------------------------------
cat <<'EOF' > ~/.xinitrc
#!/bin/sh
exec i3
EOF
chmod +x ~/.xinitrc
append_once 'if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then exec startx; fi' ~/.bash_profile
systemctl --user enable --now pipewire pipewire-pulse wireplumber

echo "=== SETUP FINISHED. REBOOT NOW. ==="
