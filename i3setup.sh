#!/bin/bash

# Exit on any error
set -e

# --- 1. Internet Connection Check ---
echo "Checking internet connection..."
until ping -c 1 google.com >/dev/null 2>&1; do
    echo "Network is down! Please connect to Wi-Fi (run 'nmtui')."
    echo "Retrying in 5 seconds..."
    sleep 5
done
echo "Internet connected!"

# --- 2. Install Software ---
echo "Installing packages..."
# Removed 'pacman-contrib' as it is no longer needed for the update block
sudo pacman -S --needed --noconfirm \
    firefox kitty mousepad thunar thunar-volman gvfs udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent nvtop htop i3blocks \
    pavucontrol libva-nvidia-driver dex xorg-xinit xorg-xrandr \
    wget git

# --- 3. Adjust Fonts ---
echo "Configuring fonts..."
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

# --- 4. Kitty Terminal Config ---
mkdir -p ~/.config/kitty
cat <<EOF > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0
confirm_os_window_close 0
EOF

# --- 5. Firefox with VAAPI ---
echo "Configuring Firefox..."
pkill firefox || true
mkdir -p ~/.mozilla/firefox/
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

# --- 6. i3blocks Config ---
mkdir -p ~/.config/i3blocks/
cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff
align=center

[cpu]
label=CPU: 
min_width=CPU: 100°C
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then kitty -e htop; fi; sensors | grep 'Package id 0' | awk '{print int($4)}' | sed 's/$/°C/'
interval=1

[gpu]
label=GPU: 
min_width=GPU: 100°C
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then kitty -e nvtop; fi; nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | awk '{print $1"°C"}'
interval=1

[disk]
label=SSD: 
min_width=SSD: 100%
instance=/
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then kitty -e bash -c "df -h; exec bash"; fi; df -h / | awk '/\// {print $5}'
interval=30

[memory]
label=RAM: 
min_width=RAM: 100%
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then kitty -e htop; fi; free | grep Mem | awk '{printf "%.0f%%\n", $3/$2 * 100}'
interval=1

[wireless]
label=NET: 
min_width=NET: 100%
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then kitty -e nmtui; fi; nmcli -t -f SIGNAL,ACTIVE device wifi | grep 'yes' | cut -d: -f1 | sed 's/$/%/'
interval=5

[volume]
label=VOL: 
min_width=VOL: 100%
command=if [ "${BLOCK_BUTTON:-0}" -eq 1 ]; then pavucontrol & fi; pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo "Muted" || (pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '[0-9]+(?=%)' | head -n 1 | sed 's/$/%/')
interval=once
signal=10

[time]
min_width=2026-00-00 00:00
command=date '+%Y-%m-%d %H:%M'
interval=1
EOF

# --- 7. i3 Main Config ---
mkdir -p ~/.config/i3/
cat <<'EOF' > ~/.config/i3/config
set $mod Mod4
font pango:Inter Medium 11

exec --no-startup-id dex --autostart --environment i3
exec_always --no-startup-id xrandr --output DP-0 --mode 1920x1080 --rate 239.96
exec --no-startup-id setxkbmap -layout us -option compose:ralt
exec_always --no-startup-id xset s off
exec_always --no-startup-id xset s noblank
exec_always --no-startup-id xset -dpms

set $refresh_volume exec --no-startup-id pkill -RTMIN+10 i3blocks
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +1% && pkill -RTMIN+10 i3blocks
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -1% && pkill -RTMIN+10 i3blocks
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && pkill -RTMIN+10 i3blocks

floating_modifier $mod
tiling_drag modifier titlebar

bindsym $mod+Return exec kitty
bindsym $mod+b exec --no-startup-id MOZ_DISABLE_RDD_SANDBOX=1 LIBVA_DRIVER_NAME=nvidia firefox
bindsym $mod+t exec --no-startup-id thunar
bindsym $mod+n exec --no-startup-id mousepad
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+q kill

bindsym Control+Mod1+End exec poweroff
bindsym Control+Mod1+Home exec reboot

bindsym $mod+j focus left
bindsym $mod+k focus down
bindsym $mod+l focus up
bindsym $mod+semicolon focus right
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+j move left
bindsym $mod+Shift+k move down
bindsym $mod+Shift+l move up
bindsym $mod+Shift+semicolon move right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle
bindsym $mod+a focus parent

set $ws1 "1"
set $ws2 "2"
set $ws3 "3"
set $ws4 "4"
set $ws5 "5"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"

bindsym $mod+1 workspace number $ws1
bindsym $mod+2 workspace number $ws2
bindsym $mod+3 workspace number $ws3
bindsym $mod+4 workspace number $ws4
bindsym $mod+5 workspace number $ws5
bindsym $mod+6 workspace number $ws6
bindsym $mod+7 workspace number $ws7
bindsym $mod+8 workspace number $ws8
bindsym $mod+9 workspace number $ws9
bindsym $mod+0 workspace number $ws10

bindsym $mod+Shift+1 move container to workspace number $ws1
bindsym $mod+Shift+2 move container to workspace number $ws2
bindsym $mod+Shift+3 move container to workspace number $ws3
bindsym $mod+Shift+4 move container to workspace number $ws4
bindsym $mod+Shift+5 move container to workspace number $ws5
bindsym $mod+Shift+6 move container to workspace number $ws6
bindsym $mod+Shift+7 move container to workspace number $ws7
bindsym $mod+Shift+8 move container to workspace number $ws8
bindsym $mod+Shift+9 move container to workspace number $ws9
bindsym $mod+Shift+0 move container to workspace number $ws10

bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"

mode "resize" {
    bindsym j resize shrink width 10 px or 10 ppt
    bindsym k resize grow height 10 px or 10 ppt
    bindsym l resize shrink height 10 px or 10 ppt
    bindsym semicolon resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

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

# --- 8. Power & Mouse Settings ---
sudo systemctl mask suspend.target hibernate.target hybrid-sleep.target
sudo mkdir -p /etc/X11/xorg.conf.d/
cat <<EOF | sudo tee /etc/X11/xorg.conf.d/50-mouse-acceleration.conf
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
EOF

# --- 9. TTY Auto-startx ---
sudo systemctl disable lightdm.service 2>/dev/null || true
sudo pacman -R --noconfirm lightdm lightdm-gtk-greeter 2>/dev/null || true

cat <<'EOF' > ~/.xinitrc
#!/bin/sh
[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources
[[ -f ~/.Xmodmap ]] && xmodmap ~/.Xmodmap
setxkbmap -layout us -option compose:ralt &
if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi
exec i3
EOF
chmod +x ~/.xinitrc

if ! grep -q "startx" ~/.bash_profile; then
cat <<'EOF' >> ~/.bash_profile
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  exec startx
fi
EOF
fi

# --- 10. Audio and Video ---
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat <<EOF > ~/.config/pipewire/pipewire.conf.d/bitperfect.conf
context.properties = {
    default.clock.rate = 44100
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

mkdir -p ~/.config/mpv
cat <<EOF > ~/.config/mpv/mpv.conf
vo=gpu-next
gpu-api=vulkan
hwdec=nvdec
EOF

echo "Done! Rebooting..."
sleep 2
reboot
