#!/usr/bin/env bash
set -euo pipefail

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

rpm-ostree override remove firefox firefox-langpacks

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub org.baedert.whatsnew.Flatseal org.mozilla.firefox com.valvesoftware.Steam

sudo systemctl disable bluetooth.service
sudo systemctl mask bluetooth.service

sudo systemctl disable sshd.service
sudo systemctl mask sshd.service

sudo systemctl enable --now firewalld.service
sudo firewall-cmd --set-default-zone=drop
sudo firewall-cmd --runtime-to-permanent

sudo sysctl -w net.ipv4.conf.all.rp_filter=1
sudo sysctl -w net.ipv4.conf.default.rp_filter=1
sudo sysctl -w net.ipv4.icmp_echo_ignore_all=1

sudo udevadm control --reload-rules
