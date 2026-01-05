#!/bin/bash

set -e

# --- 1. Wi-Fi Password Input & Initial Connection ---
echo "Network configuration for: AP 124-5G"
read -s -p "Enter Wi-Fi password: " WIFI_PASS
echo -e "\nConnecting to AP 124-5G..."

iwctl --passphrase "$WIFI_PASS" station wlan0 connect "AP 124-5G"

echo "Validating connection..."
MAX_RETRIES=5
COUNT=0
while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Error: Could not establish internet connection."
        exit 1
    fi
    echo "Waiting for connection (Attempt $((COUNT+1))/$MAX_RETRIES)..."
    sleep 3
    ((COUNT++))
done
echo "Connected successfully!"

# --- 2. iwd + systemd-resolved ---
sudo mkdir -p /etc/iwd
cat <<EOF | sudo tee /etc/iwd/main.conf
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF

sudo systemctl enable --now iwd
sudo systemctl enable --now systemd-resolved

# --- 3. Install Software ---
echo "Installing essential packages..."
sudo pacman -S --needed --noconfirm \
    i3-wm dmenu i3blocks firefox kitty lf micro nano \
    udiskie udisks2 dex \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent gimp \
    nvtop htop wavemon lm_sensors \
    libva-nvidia-driver nvidia-utils \
    xorg-xinit xorg-xset xorg-xrandr \
    pipewire wireplumber \
    wget git wireless-regdb maim playerctl \
    zip unzip

# --- 4. Fontconfig ---
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

# --- 5. Kitty ---
mkdir -p ~/.config/kitty
cat <<EOF > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
font_size        11.0
confirm_os_window_close 0
background_opacity 0.95
EOF

# --- 6. Firefox VAAPI ---
timeout 4s firefox --headless || true

FF_PROF=$(find ~/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default-release" | head -n 1)
[ -z "$FF_PROF" ] && FF_PROF=$(find ~/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default" | head -n 1)

if [ -n "$FF_PROF" ]; then
cat <<EOF >> "$FF_PROF/user.js"
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("gfx.webrender.all", true);
EOF
fi

# --- 7. i3blocks ---
mkdir -p ~/.config/i3blocks
cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff
align=center

[cpu]
label=CPU: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e htop >/dev/null 2>&1 & fi; USAGE=$(top -bn1 | awk -F',' '/Cpu/ {print 100-$4}'); TEMP=$(sensors | awk '/Package id 0/ {print int($4)}'); printf "%d°C [%.0f%%]\n" "$TEMP" "$USAGE"
interval=2

[gpu]
label=GPU: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e nvtop >/dev/null 2>&1 & fi; GPU_DATA=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null); read T U <<< "$GPU_DATA"; printf "%d°C [%d%%]\n" "$T" "$U"
interval=2

[memory]
label=RAM: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty --hold -e free -h >/dev/null 2>&1 & fi; free -m | awk '/Mem:/ {printf "%.1fG [%.0f%%]\n", $3/1024, ($3/$2)*100}'
interval=2

[disk]
label=SSD: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty --hold -e df -h >/dev/null 2>&1 & fi; df -h --output=used,pcent / | tail -1 | awk '{printf "%s [%s]\n", $1, $2}'
interval=60

[wireless]
label=NET: 
command=SSID=$(iwctl station wlan0 show | awk -F'network' '/Connected/ {print $2}'); SIGNAL=$(awk '/wlan0:/ {print int($3*100/70)}' /proc/net/wireless); [ -z "$SSID" ] && echo OFF || echo "$SSID [$SIGNAL%]"
interval=5

[volume]
label=VOL: 
command=if pactl get-sink-mute @DEFAULT_SINK@ | grep -q yes; then echo MUTE; else pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}'; fi
interval=once
signal=10

[time]
command=date '+%Y-%m-%d %H:%M'
interval=1
EOF

# --- 8. i3 ---
mkdir -p ~/.config/i3
cat <<'EOF' > ~/.config/i3/config
set $mod Mod4
font pango:Inter Medium 11

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id setxkbmap -layout us -option compose:ralt
exec_always --no-startup-id xrandr --output DP-0 --mode 1920x1080 --rate 239.96
exec_always --no-startup-id xset s off -dpms
exec --no-startup-id udiskie &

set $refresh_volume pkill -RTMIN+10 i3blocks

bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +1% && $refresh_volume
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -1% && $refresh_volume
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_volume

bindsym Print exec mkdir -p ~/Pictures && maim ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bindsym $mod+Return exec kitty
bindsym $mod+b exec MOZ_DISABLE_RDD_SANDBOX=1 LIBVA_DRIVER_NAME=nvidia firefox
bindsym $mod+d exec dmenu_run
bindsym $mod+q kill

bar {
    font pango:JetBrains Mono 11
    status_command i3blocks
    position bottom
}
EOF

# --- 9. X11 Mouse ---
sudo mkdir -p /etc/X11/xorg.conf.d
cat <<EOF | sudo tee /etc/X11/xorg.conf.d/50-mouse.conf
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
EndSection
EOF

# --- 10. startx ---
cat <<'EOF' > ~/.xinitrc
exec i3
EOF
chmod +x ~/.xinitrc

grep -q startx ~/.bash_profile 2>/dev/null || \
echo 'if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then exec startx; fi' >> ~/.bash_profile

# --- 11. Audio ---
systemctl --user enable --now pipewire wireplumber

# --- 12. lf ---
mkdir -p ~/.config/lf
cat <<EOF > ~/.config/lf/lfrc
set drawbox true
set icons true
set preview true
map <delete> $rm -rI $fx
map <enter> $nano $f
map <esc> clear
EOF

echo "Setup complete. Rebooting..."
sleep 2
reboot
