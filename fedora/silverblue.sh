#!/usr/bin/env bash
set -euo pipefail

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

rpm-ostree override remove firefox firefox-langpacks

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub com.github.tchx84.Flatseal org.mozilla.firefox com.valvesoftware.Steam

sudo systemctl disable bluetooth.service
sudo systemctl mask bluetooth.service

sudo systemctl disable sshd.service
sudo systemctl mask sshd.service

sudo systemctl enable --now firewalld.service
sudo firewall-cmd --set-default-zone=drop
sudo firewall-cmd --runtime-to-permanent

gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

sudo sysctl -w net.ipv4.conf.all.rp_filter=1
sudo sysctl -w net.ipv4.conf.default.rp_filter=1
sudo sysctl -w net.ipv4.icmp_echo_ignore_all=1

sudo udevadm control --reload-rules
