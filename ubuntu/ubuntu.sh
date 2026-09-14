#!/bin/bash
set -e

sudo systemctl disable --now bluetooth
sudo systemctl disable --now ModemManager

gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

sudo apt install -y python3-nautilus && mkdir -p ~/.local/share/nautilus-python/extensions && printf '%s\n' 'from gi.repository import Nautilus, GObject' 'import subprocess' '' 'class OpenInTextEditor(GObject.GObject, Nautilus.MenuProvider):' '    def get_file_items(self, files):' '        if not files:' '            return []' '        item = Nautilus.MenuItem(name="OpenInTextEditor::Open", label="Open in Text Editor")' '        item.connect("activate", self.open_files, files)' '        return [item]' '' '    def get_background_items(self, current_folder):' '        return []' '' '    def open_files(self, item, files):' '        for file in files:' '            if file.get_uri_scheme() == "file":' '                subprocess.Popen(["gnome-text-editor", file.get_location().get_path()])' > ~/.local/share/nautilus-python/extensions/open_in_text_editor.py && nautilus -q
