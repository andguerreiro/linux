#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_URI="ipp://192.168.15.200/ipp/print"

echo "=== 1. Installing i3 & Minimalist Tools ==="
sudo pacman -S --needed --noconfirm \
    i3-wm dmenu i3blocks firefox kitty lf micro udiskie udisks2 \
    noto-fonts inter-font ttf-jetbrains-mono-nerd \
    libreoffice-fresh mpv qbittorrent gimp nvtop htop wavemon \
    nvidia-utils dex xorg-xinit xorg-xset xorg-xrandr \
    pipewire wireplumber lm_sensors wget git nano wireless-regdb maim playerctl \
    zip unzip nftables localsend cups cups-filters ghostscript \
    python-matplotlib python-numpy python python-pip glow

echo -e "\n=== 2. Configuring Firewall (nftables & UFW) ==="
sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority filter;
        policy drop;
        iifname "lo" accept
        ct state invalid drop
        ct state established,related accept
        meta l4proto icmp accept
        meta l4proto icmpv6 accept
    }
    chain forward {
        type filter hook forward priority filter;
        policy drop;
    }
    chain output {
        type filter hook output priority filter;
        policy accept;
    }
}
EOF
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
if systemctl is-active --quiet ufw; then
    sudo ufw allow from 192.168.15.0/24 to any port 53317 proto tcp
    sudo ufw allow from 192.168.15.0/24 to any port 53317 proto udp
fi

echo -e "\n=== 3. Configuring Git & SSH ==="
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$KEY_PATH" ]; then
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_PATH" -N ""
fi
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$KEY_PATH"

SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
fi
chmod 600 "$SSH_CONFIG"

echo -e "\n=== 4. Setting up UDEV Rules (Keychron & VXE) ==="
sudo tee /etc/udev/rules.d/99-keychron.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
EOF
sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF
sudo tee /etc/udev/rules.d/99-vxe.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

echo -e "\n=== 5. PipeWire & Printer Setup ==="
systemctl --user enable --now pipewire wireplumber
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber

sudo systemctl enable --now cups.service
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m IPPEverywhere.ppd
sudo lpadmin -p "$PRINTER_NAME" -o PageSize=A4 -o cupsPrintQuality=Draft -o ColorModel=Gray
lpoptions -d "$PRINTER_NAME"

echo -e "\n=== 6. X11 Inputs, Autostart, & Boot Settings ==="
sudo bootctl set-timeout 0
sudo mkdir -p /etc/X11/xorg.conf.d/
cat <<EOF | sudo tee /etc/X11/xorg.conf.d/50-mouse.conf
Section "InputClass"
    Identifier "My Mouse"
    Driver "libinput"
    MatchIsPointer "yes"
    Option "AccelProfile" "flat"
EndSection
EOF

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

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Setup completed. Reboot when ready."
