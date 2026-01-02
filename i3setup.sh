#!/bin/bash

# Exit on any error
set -e

# --- 1. Wi-Fi Password Input & Check ---
# Pergunta a senha de forma segura (sem mostrar os caracteres enquanto digita)
echo "Configuração de rede para: AP 124-5G"
read -s -p "Digite a senha do Wi-Fi: " WIFI_PASS
echo -e "\nSenha capturada. Iniciando instalação..."

echo "Checking internet connection..."
until ping -c 1 8.8.8.8 >/dev/null 2>&1; do
    echo "Network is down! Waiting for connection..."
    echo "Retrying in 5 seconds..."
    sleep 5
done
echo "Internet connected!"

# --- 2. Install Software ---
echo "Installing packages..."
sudo pacman -S --needed --noconfirm \
    firefox kitty mousepad thunar thunar-volman gvfs udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent nvtop htop i3blocks \
    pavucontrol libva-nvidia-driver dex xorg-xinit xorg-xrandr \
    wget git iwd

# --- 3. Configure iwd and DNS (Fix Network & DNS) ---
echo "Configuring iwd and DNS..."

# Remove o NetworkManager e o Applet (ícone) para evitar conflitos
sudo systemctl disable --now NetworkManager 2>/dev/null || true
sudo pacman -Rs --noconfirm networkmanager network-manager-applet 2>/dev/null || true

# Configura iwd para usar o systemd-resolved como backend de DNS
sudo mkdir -p /etc/iwd
cat <<EOF | sudo tee /etc/iwd/main.conf
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF

# Pré-configura sua rede Wi-Fi específica usando a variável WIFI_PASS
sudo mkdir -p /var/lib/iwd
cat <<EOF | sudo tee "/var/lib/iwd/AP 124-5G.psk"
[Settings]
AutoConnect=true

[Security]
Passphrase=$WIFI_PASS
EOF
sudo chmod 600 "/var/lib/iwd/AP 124-5G.psk"

# Habilita serviços e fixa o resolv.conf
sudo systemctl enable --now iwd
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# --- 4. Adjust Fonts ---
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

# --- 5. Kitty Terminal Config ---
mkdir -p ~/.config/kitty
cat <<EOF > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0
confirm_os_window_close 0
EOF

# --- 6. Firefox with VAAPI ---
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

# --- 7. i3blocks Config ---
mkdir -p ~/.config/i3blocks/
cat <<'EOF' > ~/.config/i3blocks/config
separator=true
separator_block_width=15
color=#ffffff
align=center

[cpu]
label=CPU: 
command=TEMP=$(sensors | grep 'Package id 0' | awk '{print int($4)}'); USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'); printf "%d°C (%.0f%%)\n" "$TEMP" "$USAGE"
interval=2
min_width=CPU: 100°C (100%)

[gpu]
label=GPU: 
command=T=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits); U=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits); printf "%d°C (%d%%)\n" "$T" "$U"
interval=2
min_width=GPU: 100°C (100%)

[disk]
label=SSD: 
instance=/
command=df -h / | awk '/\// {gsub(/[A-Z]/,"",$3); gsub(/[A-Z]/,"",$2); printf "%s/%sGB (%s)\n", $3, $2, $5}'
interval=30
min_width=SSD: 000.0/000.0GB (100%)

[memory]
label=RAM: 
command=free -m | awk '/Mem:/ {printf "%.1f/%.1fGB (%.0f%%)\n", $3/1024, $2/1024, ($3/$2)*100}'
interval=2
min_width=RAM: 16.0/16.0GB (100%)

[wireless]
label=NET: 
command=dbm=$(iwctl station wlan0 show | awk '/AverageRSSI/ {print $2}'); if [ -z "$dbm" ]; then echo "OFF"; else val=$(( (dbm + 100) * 2 )); [ $val -gt 100 ] && val=100; [ $val -lt 0 ] && val=0; echo "$val%"; fi
interval=5
min_width=NET: 100%

[volume]
label=VOL: 
command=pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo "Muted" || (pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '[0-9]+(?=%)' | head -n 1 | sed 's/$/%/')
interval=once
signal=10
min_width=VOL: 100%

[time]
command=date '+%Y-%m-%d %H:%M'
interval=1
min_width=2026-00-00 00:00
EOF

# --- 8. i3 Main Config ---
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

# Garante que o volume apareça no boot
exec --no-startup-id sleep 2 && pkill -RTMIN+10 i3blocks

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

bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+h split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

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

# --- 9. Power & Mouse Settings ---
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

# --- 10. TTY Auto-startx ---
sudo systemctl disable lightdm.service 2>/dev/null || true
sudo pacman -R --noconfirm lightdm lightdm-gtk-greeter 2>/dev/null || true

cat <<'EOF' > ~/.xinitrc
#!/bin/sh
[[ -f ~/.Xresources ]] && xrdb -merge -I$HOME ~/.Xresources
setxkbmap -layout us -option compose:ralt &
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

# --- 11. Audio and Video ---
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

echo "Done! Sistema pronto. Reiniciando..."
sleep 2
reboot
