#!/usr/bin/env bash
set -euo pipefail

# Configuration Variables
GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_HOST="192.168.15.200"
PRINTER_URI="ipp://${PRINTER_HOST}/ipp/print"

echo "=== 1. Package Update & Installing Core Tools ==="
sudo apt update
sudo apt install -y git openssh-client nftables chromium cups cups-filters ghostscript

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

echo -e "\n=== 3. Configuring nftables Firewall ==="
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

echo -e "\n=== 4. Setting up UDEV Rules (Keychron & VXE) ==="
getent group plugdev >/dev/null || sudo groupadd plugdev
sudo usermod -aG plugdev "$USER"

# Keychron rules
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3434", MODE="0660", GROUP="plugdev"
EOF
sudo tee /etc/udev/rules.d/90-keychron-link.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="d030", TEST=="power/control", ATTR{power/control}="on"
EOF

# VXE rules
sudo tee /etc/udev/rules.d/99-vxe-webhid.rules > /dev/null <<'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="3554", MODE="0660", GROUP="plugdev"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo -e "\n=== 5. Optimizing Boot & Disabling Unnecessary Services ==="
# GRUB fast boot
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

# Disable background services
sudo systemctl disable --now bluetooth.service 2>/dev/null || true
sudo systemctl disable --now ModemManager.service 2>/dev/null || true
sudo systemctl disable --now switcheroo-control 2>/dev/null || true
sudo systemctl disable --now packagekit.service 2>/dev/null || true
sudo systemctl disable --now avahi-daemon.socket 2>/dev/null || true
sudo systemctl disable --now avahi-daemon 2>/dev/null || true

echo -e "\n=== 6. Purging KDE Bloatware ==="
sudo apt purge -y xterm vim kmail* konqueror kontrast kdeconnect akregator bluez imagemagick imagemagick-7.q16 plasma-discover
sudo apt autoremove -y && sudo apt autoclean

echo -e "\n=== 7. Installing & Configuring Printer (Offline Safe) ==="
sudo systemctl enable --now cups.service
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m everywhere
sudo lpadmin -p "$PRINTER_NAME" -o PageSize=A4 -o print-quality=3 -o ColorModel=Gray
lpoptions -d "$PRINTER_NAME"

echo -e "\n=== 8. Configuring PipeWire Sample Rates ==="
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 ]
}
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo -e "\n=============================================================="
echo " SETUP COMPLETE!"
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo "⚠️  Log out and back in (or reboot) for group permissions and GRUB changes."
