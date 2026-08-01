#!/bin/bash
set -e

sudo systemctl disable --now bluetooth.service
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

gsettings set org.gnome.mutter center-new-windows true
