#!/bin/bash

# Abort on error
set -e

# --- 1. Wi-Fi Password Input & Initial Connection ---
echo "Network configuration for: AP 124-5G"
read -s -p "Enter Wi-Fi password: " WIFI_PASS
echo -e "\nConnecting to AP 124-5G..."

# Use the captured password to connect immediately
iwctl --passphrase "$WIFI_PASS" station wlan0 connect "AP 124-5G"

# Validation: Wait a few seconds and check for internet
echo "Validating connection..."
MAX_RETRIES=5
COUNT=0
while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Error: Could not establish internet connection. Check your password."
        exit 1
    fi
    echo "Waiting for connection (Attempt $((COUNT+1))/$MAX_RETRIES)..."
    sleep 3
    ((COUNT++))
done
echo "Connected successfully!"

# --- 2. Configure iwd and DNS Persistence ---
sudo mkdir -p /etc/iwd
cat <<EOF | sudo tee /etc/iwd/main.conf
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF

sudo mkdir -p /var/lib/iwd
cat <<EOF | sudo tee "/var/lib/iwd/AP_124-5G.psk"
[Settings]
AutoConnect=true

[Security]
Passphrase=$WIFI_PASS
EOF
sudo chmod 600 "/var/lib/iwd/AP_124-5G.psk"

sudo systemctl enable --now iwd
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# --- 3. Install Software (Pure Minimalist CLI/TUI) ---
echo "Installing essential packages..."
sudo pacman -S --needed --noconfirm \
    i3-wm dmenu i3blocks firefox kitty lf micro udiskie udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent gimp nvtop htop wavemon \
    libva-nvidia-driver nvidia-utils dex xorg-server xorg-xinit xorg-xset xorg-xrandr \
    pipewire-pulse wireplumber lm_sensors wget git nano wireless-regdb maim playerctl

# --- 4. Adjust Fonts ---
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

# --- 5. Kitty Terminal Config ---
mkdir -p ~/.config/kitty
cat <<EOF > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
font_size        11.0
confirm_os_window_close 0
background_opacity 0.95
EOF

# --- 6. Firefox Hardware Acceleration ---
timeout 4s firefox --headless || true
FF_PROF=$(find ~/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default-release" | head -n 1)
[ -z "$FF_PROF" ] && FF_PROF=$(find ~/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default" | head -n 1)

if [ -n "$FF_PROF" ]; then
    touch "$FF_PROF/user.js"
    cat <<EOF >> "$FF_PROF/user.js"
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
user_pref("gfx.webrender.all", true);
EOF
fi

# --- 7. i3blocks Config ---
mkdir -p ~/.config/i3blocks/
cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff
align=center

[cpu]
label=CPU: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e htop >/dev/null 2>&1 & fi; USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'); TEMP=$(sensors | awk '/Package id 0/ {print int($4)}'); printf "%d°C [%.0f%%]\n" "$TEMP" "$USAGE"
interval=2

[gpu]
label=GPU: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e nvtop >/dev/null 2>&1 & fi; GPU_DATA=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | sed 's/, / /'); read T U <<< "$GPU_DATA"; [ -z "$T" ] && echo "OFF" || printf "%d°C [%d%%]\n" "$T" "$U"
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
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e wavemon; fi; SSID=$(iwctl station wlan0 show | awk -F'network' '/Connected network/ {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'); if [ -z "$SSID" ]; then echo "OFF"; else SIGNAL=$(awk '/wlan0:/ {print int($3 * 100 / 70)}' /proc/net/wireless); echo "$SSID [$SIGNAL%]"; fi
interval=5

[volume]
label=VOL: 
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e pw-top >/dev/null 2>&1 & fi; pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}'
interval=once
signal=10

[time]
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty --hold -e cal -y; fi; date '+%Y-%m-%d %H:%M '
interval=1
EOF

# --- 8. i3 Main Config ---
mkdir -p ~/.config/i3/
cat <<'EOF' > ~/.config/i3/config
set $mod Mod4
font pango:Inter Medium 11

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id setxkbmap -layout us -option compose:ralt
exec --no-startup-id sleep 2 && pkill -RTMIN+10 i3blocks
exec_always --no-startup-id xrandr --output DP-0 --mode 1920x1080 --rate 239.96
exec_always --no-startup-id xset s off -dpms
exec --no-startup-id udiskie &

floating_modifier $mod
tiling_drag modifier titlebar

set $refresh_volume exec --no-startup-id pkill -RTMIN+10 i3blocks
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +1% && pkill -RTMIN+10 i3blocks
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -1% && pkill -RTMIN+10 i3blocks
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && pkill -RTMIN+10 i3blocks
bindsym XF86AudioPlay exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext exec --no-startup-id playerctl next
bindsym XF86AudioPrev exec --no-startup-id playerctl previous

bindsym Print exec --no-startup-id mkdir -p ~/Pictures && maim ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bindsym $mod+Print exec --no-startup-id maim -s ~/Pictures/$(date +%Y%m%d_%H%M%S).png

bindsym $mod+Return exec kitty
bindsym $mod+b exec --no-startup-id MOZ_DISABLE_RDD_SANDBOX=1 LIBVA_DRIVER_NAME=nvidia firefox
bindsym $mod+l exec --no-startup-id kitty -e lf
bindsym $mod+m exec --no-startup-id kitty -e micro
bindsym $mod+d exec --no-startup-id dmenu_run
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
        bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

bar {
    font pango:JetBrains Mono 11
    status_command i3blocks -c ~/.config/i3blocks/config
    position bottom
    colors {
        background #121212
        statusline #ffffff
        separator  #666666
    }
}
EOF

# --- 9. X11 Mouse & Monitor ---
sudo mkdir -p /etc/X11/xorg.conf.d/
cat <<EOF | sudo tee /etc/X11/xorg.conf.d/50-mouse.conf
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
EndSection
EOF

# --- 10. TTY Auto-startx ---
cat <<'EOF' > ~/.xinitrc
#!/bin/sh
[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources
setterm -blank 0 -powersave off -powerdown 0
exec i3
EOF
chmod +x ~/.xinitrc

if ! grep -q "startx" ~/.bash_profile; then
echo 'if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then exec startx; fi' >> ~/.bash_profile
fi

# --- 11. Audio Config ---
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# --- 12. lf Config ---
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
