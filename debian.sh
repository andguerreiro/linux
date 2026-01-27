#!/usr/bin/env bash
set -euo pipefail

echo "== Debian post-install hardening & cleanup =="

#----------------------------
# GRUB – set timeout to 0
#----------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub || true
grep -q "^GRUB_TIMEOUT=" /etc/default/grub || echo "GRUB_TIMEOUT=0" >> /etc/default/grub
update-grub

#----------------------------
# Firewall (UFW)
#----------------------------
echo "[UFW] Installing and configuring firewall"
apt install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

#----------------------------
# Disable Bluetooth
#----------------------------
echo "[Bluetooth] Disabling bluetooth.service"
systemctl disable --now bluetooth.service || true

#----------------------------
# Purge unwanted GNOME software
#----------------------------
echo "[GNOME] Purging unwanted GNOME packages"
apt purge -y \
    gnome-games \
    gnome-characters \
    gnome-clocks \
    gnome-calendar \
    gnome-color-manager \
    gnome-contacts \
    gnome-font-viewer \
    gnome-logs \
    gnome-maps \
    gnome-music \
    gnome-sound-recorder \
    gnome-weather \
    gnome-tour \
    totem \
    im-config \
    evolution \
    rhythmbox \
    shotwell \
    yelp \
    simple-scan \
    gnome-snapshot \
    gnome-tweaks || true

apt autoremove -y

#----------------------------
# GNOME customization (user session)
#----------------------------
if [[ -n "${SUDO_USER:-}" ]]; then
    echo "[GNOME] Applying gsettings for user: $SUDO_USER"
    sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" \
        gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false || true

    sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" \
        gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1 || true
else
    echo "[GNOME] Skipped gsettings (no SUDO_USER detected)"
fi

#----------------------------
# PipeWire – bit-perfect audio
#----------------------------
if [[ -n "${SUDO_USER:-}" ]]; then
    echo "[PipeWire] Configuring bit-perfect sample rates"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    PIPEWIRE_DIR="$USER_HOME/.config/pipewire/pipewire.conf.d"

    mkdir -p "$PIPEWIRE_DIR"
    cat > "$PIPEWIRE_DIR/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config"

    sudo -u "$SUDO_USER" systemctl --user restart pipewire pipewire-pulse wireplumber || true
fi

#----------------------------
# Enable contrib / non-free repositories
#----------------------------
echo "[APT] Enabling contrib and non-free repositories"
sed -i -E 's/(^deb.* main)([^#]*)/\1 contrib non-free non-free-firmware/' /etc/apt/sources.list
apt update

echo "== Post-install complete. Reboot recommended. =="
