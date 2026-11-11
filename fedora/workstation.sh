#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_HOST="192.168.15.200"
PRINTER_URI="ipp://${PRINTER_HOST}/ipp/print"

echo "=== 1. System Upgrade & Repositories ==="
sudo dnf upgrade --refresh -y
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo -e "\n=== 2. Installing Packages (Git, OpenSSH, Chromium, CUPS) ==="
sudo dnf install -y git openssh-clients chromium cups cups-filters

echo -e "\n=== 3. Configuring Git & SSH ==="
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

echo -e "\n=== 4. Setting up Keychron UDEV Rules ==="
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

echo -e "\n=== 5. Applying GRUB & System Tweaks ==="
# Set GRUB timeout to 0
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
else
    echo 'GRUB_TIMEOUT=0' | sudo tee -a /etc/default/grub >/dev/null
fi
sudo grub2-mkconfig -o /etc/grub2.cfg

# Disable Bluetooth service
sudo systemctl disable --now bluetooth.service || true

# Apply GNOME desktop settings
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo -e "\n=== 6. Replacing RPM Firefox with Flatpak ==="
sudo dnf remove -y firefox firefox-langpacks || true
rm -rf ~/.mozilla ~/.cache/mozilla ~/.config/mozilla ~/.cache/firefox ~/.config/firefox
flatpak install -y flathub org.mozilla.firefox

echo -e "\n=== 7. Installing & Configuring Printer (Offline Safe) ==="
sudo systemctl enable --now cups.service
sudo lpadmin \
    -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_URI" \
    -m everywhere

sudo lpadmin \
    -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray \
    -o printer-is-shared=false

lpoptions -d "$PRINTER_NAME"

echo -e "\n=== 8. Configuring PipeWire Sample Rates ==="
install -d ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf <<'EOF'
context.properties = {
  default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF
systemctl --user restart pipewire wireplumber || true

echo -e "\n=== 9. Cleanup ==="
sudo dnf autoremove -y

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Reboot your system for GRUB and udev changes to take effect."
