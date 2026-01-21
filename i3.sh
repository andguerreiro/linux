#!/bin/bash

set -e

# --- 1. Install Software (Pure Minimalist CLI/TUI) ---

sudo pacman -S --needed --noconfirm \
    i3-wm dmenu i3blocks firefox kitty lf micro udiskie udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent gimp nvtop htop wavemon \
    nvidia-utils dex xorg-xinit xorg-xset xorg-xrandr \
    pipewire wireplumber lm_sensors wget git nano wireless-regdb maim playerctl \
    zip unzip spotify-launcher

# --- 2. Adjust Fonts ---

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

# --- 3. Kitty Terminal Config ---

mkdir -p ~/.config/kitty

cat <<EOF > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
font_size        11.0
confirm_os_window_close 0
background_opacity 0.95
EOF

# --- 4. i3blocks Config ---

mkdir -p ~/.config/i3blocks/

cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff
align=center

[cpu]
label=CPU: 
command=TEMP=$(sensors -u coretemp-isa-* 2>/dev/null | awk '/temp1_input/ {printf "%.0f", $2; exit}'); PREV=$(cat /tmp/i3_cpu_prev 2>/dev/null || echo "0 0"); read P_TOTAL P_IDLE <<< "$PREV"; read TOTAL IDLE <<< "$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)"; echo "$TOTAL $IDLE" > /tmp/i3_cpu_prev; if [ "$P_TOTAL" -ne 0 ]; then USAGE=$(( (100*(TOTAL-P_TOTAL-(IDLE-P_IDLE)))/(TOTAL-P_TOTAL) )); else USAGE=0; fi; [ -z "$TEMP" ] && TEMP=0; echo "${TEMP}°C [${USAGE}%]"
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
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty -e pw-top >/dev/null 2>&1 & fi; if pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes"; then echo "MUTE"; else pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}'; fi
interval=once
signal=10

[time]
command=if [ "$BLOCK_BUTTON" -eq 1 ]; then setsid kitty --hold -e cal -y; fi; date '+%Y-%m-%d %H:%M '
interval=1
EOF

# --- 5. i3 Main Config ---

mkdir -p ~/.config/i3/

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

set $refresh_volume pkill -RTMIN+10 i3blocks
exec --no-startup-id sleep 1 && $refresh_volume

bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +1% && $refresh_volume
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -1% && $refresh_volume
bindsym XF86AudioMute         exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && $refresh_volume

bindsym XF86AudioPlay exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext exec --no-startup-id playerctl next
bindsym XF86AudioPrev exec --no-startup-id playerctl previous

bindsym Print exec --no-startup-id mkdir -p ~/Pictures && maim ~/Pictures/$(date +%Y%m%d_%H%M%S).png
bindsym $mod+Print exec --no-startup-id maim -s ~/Pictures/$(date +%Y%m%d_%H%M%S).png

bindsym $mod+Return exec kitty
bindsym $mod+b exec --no-startup-id firefox
bindsym $mod+s exec --no-startup-id spotify-launcher
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

# --- 6. X11 Mouse ---

sudo mkdir -p /etc/X11/xorg.conf.d/

cat <<EOF | sudo tee /etc/X11/xorg.conf.d/50-mouse.conf
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
EndSection
EOF

# --- 7. TTY Auto-startx ---

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

# --- 8. Audio Config ---

systemctl --user enable --now pipewire wireplumber

mkdir -p ~/.config/pipewire/pipewire.conf.d/

cat <<'EOF' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber

# --- 9. lf Config ---

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

echo "Setup complete. You may reboot when ready."
