#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_URI="ipp://192.168.15.200/ipp/print"

echo "=== 1. Installing Hyprland & Required Packages ==="
PACKAGES=(
    hyprland kitty dolphin firefox spotify-launcher playerctl
    pipewire pipewire-audio pipewire-pulse wireplumber
    waybar mako hyprlauncher networkmanager
    xdg-desktop-portal xdg-desktop-portal-hyprland
    grim slurp wl-clipboard
    ttf-dejavu ttf-liberation ttf-jetbrains-mono-nerd
    nftables localsend cups cups-filters ghostscript
    python-matplotlib python-numpy python python-pip glow
)
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

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
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0660", GROUP="wheel"
EOF
sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF
sudo tee /etc/udev/rules.d/99-vxe.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0660", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0660", GROUP="wheel"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

echo -e "\n=== 5. Enabling Services & Pipewire Sample Rates ==="
sudo systemctl enable --now NetworkManager
systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service

mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo -e "\n=== 6. Installing & Configuring Printer (Offline Safe) ==="
sudo systemctl enable --now cups.service
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m IPPEverywhere.ppd
sudo lpadmin -p "$PRINTER_NAME" -o PageSize=A4 -o cupsPrintQuality=Draft -o ColorModel=Gray
lpoptions -d "$PRINTER_NAME"

echo -e "\n=== 7. Configuring Hyprland Environments & Font/Configs ==="
sudo bootctl set-timeout 0

# Dolphin terminal config
KDEGLOBALS="$HOME/.config/kdeglobals"
mkdir -p "$HOME/.config"
if [[ -f "$KDEGLOBALS" ]]; then
    grep -vE '^(TerminalApplication|TerminalService)=' "$KDEGLOBALS" > /tmp/kdeglobals.tmp
else
    touch /tmp/kdeglobals.tmp
fi
cat >> /tmp/kdeglobals.tmp << 'EOF'
[General]
TerminalApplication=kitty
TerminalService=
EOF
mv /tmp/kdeglobals.tmp "$KDEGLOBALS"

# Fonts config
FC_DIR="$HOME/.config/fontconfig"
mkdir -p "$FC_DIR"
cat > "$FC_DIR/fonts.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <match target="pattern"><test name="family" qual="any"><string>sans</string></test><edit name="family" mode="assign" binding="strong"><string>DejaVu Sans</string></edit></match>
    <match target="pattern"><test name="family" qual="any"><string>serif</string></test><edit name="family" mode="assign" binding="strong"><string>DejaVu Serif</string></edit></match>
    <match target="pattern"><test name="family" qual="any"><string>monospace</string></test><edit name="family" mode="assign" binding="strong"><string>JetBrains Mono</string></edit></match>
</fontconfig>
EOF
fc-cache -fv

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Log out and back in to Hyprland."
