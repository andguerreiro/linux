#!/bin/bash

set -e

echo "== Updating system =="
sudo pacman -Syu --noconfirm

echo "== Installing high quality fonts =="
sudo pacman -S --needed --noconfirm \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  ttf-dejavu \
  ttf-liberation \
  ttf-firacode-nerd \
  ttf-jetbrains-mono-nerd

echo "== Configuring font preferences =="
mkdir -p ~/.config/fontconfig

cat > ~/.config/fontconfig/fonts.conf <<'FONT'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">

<fontconfig>

  <!-- Preferred monospace fonts for programming -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
      <family>FiraCode Nerd Font</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>

  <!-- Preferred general interface fonts -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>DejaVu Sans</family>
    </prefer>
  </alias>

  <!-- Preferred serif fonts -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>DejaVu Serif</family>
    </prefer>
  </alias>

</fontconfig>
FONT

echo "== Configuring GTK font rendering =="
mkdir -p ~/.config/gtk-3.0

cat > ~/.config/gtk-3.0/settings.ini <<'GTK'
[Settings]
gtk-font-name=Noto Sans 10
gtk-monospace-font-name=JetBrainsMono Nerd Font 10
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
GTK

echo "== Rebuilding font cache =="
fc-cache -fv

echo
echo "Done!"
echo "Please restart Firefox and log out/in from XFCE."
echo
echo "To verify your monospace font run:"
echo "fc-match monospace"
