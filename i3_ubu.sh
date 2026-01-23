#!/bin/bash
set -euo pipefail

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================
sudo apt update
sudo apt install -y \
  xorg xinit x11-xserver-utils x11-xkb-utils \
  i3 i3blocks dmenu dex kitty \
  lf micro nano udiskie udisks2 \
  pipewire pipewire-audio pipewire-pulse wireplumber \
  lm-sensors htop nvtop wavemon unzip zip ncal \
  maim playerctl \
  fonts-jetbrains-mono fonts-inter fonts-noto \
  network-manager iw libinput-tools ca-certificates \
  dbus policykit-1 \
  flatpak

# Install NVIDIA drivers
sudo ubuntu-drivers autoinstall

# Add Flathub and install via Flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# =============================================================================
# FONT & TERMINAL CONFIG
# =============================================================================
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

# =============================================================================
# I3BLOCKS CONFIG
# =============================================================================
mkdir -p ~/.config/i3blocks

cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff

[cpu]
label=CPU:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty -e htop >/dev/null 2>&1 & fi; sensors 2>/dev/null | awk "/Package id 0/ {print int(\$4)\"°C\"}" | xargs'
interval=5

[gpu]
label=GPU:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty -e nvtop >/dev/null 2>&1 & fi; command -v nvidia-smi >/dev/null || { echo OFF; exit; }; nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | sed "s/$/°C/" || echo OFF'
interval=5

[memory]
label=RAM:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty -e htop >/dev/null 2>&1 & fi; awk '\''BEGIN{u=0}/MemTotal/{t=$2}/MemFree/{f=$2}/Buffers/{b=$2}/^Cached:/{c=$2}/SReclaimable/{r=$2}/Shmem/{s=$2}END{u=t-f-b-c-r+s;printf "%.1fG",u/1024/1024}'\'' /proc/meminfo | xargs'
interval=5

[disk]
label=SSD:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty --hold -e df -h >/dev/null 2>&1 & fi; df -h --output=used / | tail -1 | xargs'
interval=60

[wireless]
label=NET:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty -e wavemon >/dev/null 2>&1 & fi; iface=wlxe84e069d188a; ssid=$(iw dev "$iface" link | awk "/SSID/ {print \$2}"); if [ -z "$ssid" ]; then echo "OFFLINE"; else echo "$ssid"; fi'
interval=5

[volume]
label=VOL:
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty -e pw-top >/dev/null 2>&1 & fi; wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk "{if(\$3==\"[MUTED]\") print \"MUTE\"; else print int(\$2*100)\"%\"}" | xargs'
interval=once
signal=10

[time]
command=sh -c 'if [ "$BLOCK_BUTTON" = 1 ]; then setsid kitty --hold -e cal -y >/dev/null 2>&1 & fi; date "+%Y-%m-%d %H:%M"'
interval=1
EOF

# =============================================================================
# I3 CONFIG
# =============================================================================
mkdir -p ~/.config/i3
cat <<'EOF' > ~/.config/i3/config
set $mod Mod4
font pango:Inter Medium 11

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id "sleep 1 && setxkbmap -layout us -option compose:ralt"
exec_always --no-startup-id xrandr --output DP-0 --mode 1920x1080 --rate 239.96
exec_always --no-startup-id xset s off -dpms
exec --no-startup-id udiskie &

floating_modifier $mod
tiling_drag modifier titlebar

set $refresh_volume pkill -RTMIN+10 i3blocks
bindsym XF86AudioRaiseVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+ && $refresh_volume
bindsym XF86AudioLowerVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%- && $refresh_volume
bindsym XF86AudioMute exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && $refresh_volume

bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

bindsym Print exec mkdir -p ~/Pictures && maim ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bindsym $mod+Print exec maim -s ~/Pictures/$(date +%Y%m%d_%H%M%S).png

bindsym $mod+Return exec kitty
bindsym $mod+b exec flatpak run org.mozilla.firefox
bindsym $mod+l exec kitty -e lf
bindsym $mod+m exec kitty -e micro
bindsym $mod+d exec dmenu_run
bindsym $mod+q kill

bindsym Control+Mod1+End exec poweroff
bindsym Control+Mod1+Home exec reboot

bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

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

bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+e layout toggle split
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

mode "resize" {
    bindsym Left resize shrink width 10 px or 10 ppt
    bindsym Down resize grow height 10 px or 10 ppt
    bindsym Up resize shrink height 10 px or 10 ppt
    bindsym Right resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

bar {
    font pango:JetBrains Mono 11
    status_command i3blocks
    position bottom
}
EOF

# =============================================================================
# LF CONFIG
# =============================================================================

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

# =============================================================================
# AUDIO CONFIG
# =============================================================================

systemctl --user enable --now pipewire wireplumber

mkdir -p ~/.config/pipewire/pipewire.conf.d/

cat <<'EOF' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber

# =============================================================================
# XORG & SYSTEM SETUP
# =============================================================================
sudo mkdir -p /etc/X11/xorg.conf.d

sudo tee /etc/X11/xorg.conf.d/00-keyboard.conf >/dev/null <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
    Option "XkbOptions" "compose:ralt"
EndSection
EOF

sudo tee /etc/X11/xorg.conf.d/50-mouse.conf >/dev/null <<EOF
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
EndSection
EOF

cat <<'EOF' > ~/.xinitrc
#!/bin/sh
exec dbus-run-session -- i3
EOF
chmod +x ~/.xinitrc

sudo timedatectl set-timezone America/Sao_Paulo

echo "=== Setup completed. Reboot. ==="
