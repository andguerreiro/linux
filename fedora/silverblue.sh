#!/usr/bin/env bash
set -Eeuo pipefail

sudo firewall-cmd --set-default-zone=public
sudo firewall-cmd --reload

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

sudo rpm-ostree override remove firefox firefox-langpacks || true

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub org.mozilla.firefox || sudo flatpak install -y flathub org.mozilla.firefox

sudo systemctl disable --now bluetooth.service || true
sudo systemctl mask bluetooth.service || true

sudo systemctl disable --now sshd.service || true
sudo systemctl mask sshd.service || true

sudo systemctl mask systemd-coredump.socket || true
sudo systemctl mask systemd-coredump@.service || true

gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

mkdir -p ~/.config/pipewire/pipewire.conf.d/

cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber

sudo udevadm control --reload-rules
