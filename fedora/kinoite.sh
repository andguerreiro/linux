#!/usr/bin/env bash
set -Eeuo pipefail

sudo firewall-cmd --set-default-zone=public

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

sudo rpm-ostree override remove firefox firefox-langpacks || true

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub org.mozilla.firefox || \
sudo flatpak install -y flathub org.mozilla.firefox

sudo systemctl disable --now bluetooth.service || true
sudo systemctl mask bluetooth.service || true

sudo systemctl disable --now sshd.service || true
sudo systemctl mask sshd.service || true

sudo systemctl mask systemd-coredump.socket || true
sudo systemctl mask systemd-coredump@.service || true

# PipeWire: permitir 44.1 / 48 / 96 / 192 kHz
mkdir -p ~/.config/pipewire/pipewire.conf.d/

cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber

sudo udevadm control --reload-rules
