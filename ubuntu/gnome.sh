#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_HOST="192.168.15.200"
PRINTER_URI="ipp://${PRINTER_HOST}/ipp/print"

echo "=== 1. Configuring Firewall ==="
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

echo -e "\n=== 2. Installing & Configuring Git, SSH, & CUPS ==="
sudo apt-get update
sudo apt-get install -y git openssh-client cups cups-filters ghostscript

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

echo -e "\n=== 3. Setting up UDEV Rules (Keychron & VXE) ==="
sudo groupadd -f plugdev
sudo usermod -aG plugdev "$USER"

# Keychron rules
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3434", MODE="0660", GROUP="plugdev"
EOF
sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF

# VXE rules
sudo tee /etc/udev/rules.d/99-vxe-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3554", MODE="0660", GROUP="plugdev"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo -e "\n=== 4. Configuring PipeWire Sample Rates ==="
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 ]
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo -e "\n=== 5. Applying Ubuntu System Tweaks ==="
sudo systemctl disable --now bluetooth ModemManager
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo -e "\n=== 6. Installing & Configuring Printer (Offline Safe) ==="
sudo systemctl enable --now cups.service
sudo lpadmin \
    -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_URI" \
    -m IPPEverywhere.ppd

sudo lpadmin \
    -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray \
    -o printer-is-shared=false

lpoptions -d "$PRINTER_NAME"

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Log out and back in (or reboot) for group changes to take effect."
