#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_URI="ipp://192.168.15.200/ipp/print"

echo "=== 1. Installing Packages via Pacman ==="
sudo pacman -S --needed --noconfirm \
    git openssh localsend cups cups-filters ghostscript \
    python-matplotlib python-numpy python python-pip glow

echo -e "\n=== 2. Configuring Git & SSH ==="
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

if [ ! -f "$KEY_PATH" ]; then
    echo ">>> Generating SSH key..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_PATH" -N ""
else
    echo ">>> SSH key already exists at $KEY_PATH, reusing it."
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

echo -e "\n=== 3. Setting up Keychron UDEV Rules ==="
sudo tee /etc/udev/rules.d/99-keychron.rules > /dev/null <<EOF
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", MODE="0666", GROUP="wheel"
EOF

sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo -e "\n=== 4. Configuring Firewall for LocalSend ==="
if systemctl is-active --quiet ufw; then
    sudo ufw allow from 192.168.15.0/24 to any port 53317 proto tcp
    sudo ufw allow from 192.168.15.0/24 to any port 53317 proto udp
fi

echo -e "\n=== 5. Configuring PipeWire Sample Rates ==="
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo -e "\n=== 6. Installing & Configuring Printer (Offline Safe) ==="
sudo systemctl enable --now cups.service
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m IPPEverywhere.ppd

sudo lpadmin -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray

lpoptions -d "$PRINTER_NAME"

echo -e "\n=== 7. Configuring SDDM Autologin ==="
SDDM_CONFIG="/etc/sddm.conf.d/autologin.conf"
sudo mkdir -p /etc/sddm.conf.d
sudo tee "$SDDM_CONFIG" > /dev/null <<'EOF'
[Autologin]
User=and
Session=niri.desktop
Relogin=false
EOF

echo -e "\n=== 8. Applying Niri Desktop Tweaks ==="
# Compose key in input.kdl
INPUT_CONFIG="$HOME/.config/niri/cfg/input.kdl"
if [ -f "$INPUT_CONFIG" ]; then
    grep -q 'options "compose:ralt"' "$INPUT_CONFIG" || \
    sed -i '/xkb {/a\            options "compose:ralt"' "$INPUT_CONFIG"
fi

# Volume step in keybinds.kdl
KEYBINDS_CONFIG="$HOME/.config/niri/cfg/keybinds.kdl"
if [ -f "$KEYBINDS_CONFIG" ]; then
    sed -i \
        -e 's/noctalia msg volume-up/noctalia msg volume-up 1/g' \
        -e 's/noctalia msg volume-down/noctalia msg volume-down 1/g' \
        "$KEYBINDS_CONFIG"
fi

if command -v niri &>/dev/null && pgrep -u "$USER" niri >/dev/null; then
    niri validate && niri msg action load-config-file || true
fi

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Reboot or log out/in for all permissions and autologin to take effect."
