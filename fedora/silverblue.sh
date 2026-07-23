#!/usr/bin/env bash
set -Eeuo pipefail

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

rpm-ostree override remove firefox firefox-langpacks

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub org.mozilla.firefox

sudo systemctl disable --now bluetooth.service || true
sudo systemctl mask bluetooth.service || true

sudo systemctl disable --now sshd.service || true
sudo systemctl mask sshd.service || true

sudo systemctl mask systemd-coredump.socket || true
sudo systemctl mask systemd-coredump@.service || true

sudo systemctl enable --now firewalld.service

sudo firewall-cmd --set-default-zone=public
sudo firewall-cmd --permanent --remove-service=ssh || true
sudo firewall-cmd --permanent --remove-service=cockpit || true
sudo firewall-cmd --reload

sudo tee /etc/sysctl.d/99-desktop-hardening.conf >/dev/null <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

sudo sysctl --system

gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

sudo udevadm control --reload-rules
