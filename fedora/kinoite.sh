#!/usr/bin/env bash
set -Eeuo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"

echo "=== 1. Installing Git, OpenSSH Clients & Chromium ==="
sudo dnf install -y git openssh-clients chromium

echo -e "\n=== 2. Configuring Git & SSH ==="
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

echo -e "\n=== 3. Setting up Keychron UDEV Rules ==="
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", TAG+="uaccess"
EOF

echo -e "\n=== 4. Applying Kinoite System Tweaks & Flatpak Firefox ==="
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

sudo rpm-ostree override remove firefox firefox-langpacks || true
rm -rf ~/.mozilla ~/.config/mozilla ~/.cache/mozilla

flatpak install -y flathub org.mozilla.firefox || \
sudo flatpak install -y flathub org.mozilla.firefox

sudo systemctl disable --now bluetooth.service || true
sudo systemctl mask bluetooth.service || true
sudo systemctl disable --now sshd.service || true
sudo systemctl mask sshd.service || true
sudo systemctl mask systemd-coredump.socket || true
sudo systemctl mask systemd-coredump@.service || true

echo -e "\n=== 5. Configuring PipeWire Sample Rates ==="
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Note: Because rpm-ostree was modified or services masked, a reboot"
echo "    is recommended so all changes and your Keychron rules take effect."
