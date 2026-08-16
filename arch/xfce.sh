#!/bin/bash
set -euo pipefail

sudo pacman -Rns --noconfirm vim

echo "timeout 0" | sudo tee /boot/loader/loader.conf

mkdir -p ~/.config/pipewire/pipewire.conf.d/

printf '%s\n' \
'context.properties = {' \
'    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]' \
'}' \
> ~/.config/pipewire/pipewire.conf.d/custom-rates.conf

systemctl --user restart pipewire pipewire-pulse wireplumber

mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml

cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml <<'EOF'
<?xml version="1.1" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=960;y=1066"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="24"/>
      <property name="size" type="uint" value="36"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="11"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="4"/>
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="14"/>
        <value type="int" value="5"/>
        <value type="int" value="8"/>
        <value type="int" value="12"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-8" type="string" value="clock">
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-format" type="string" value="%d %b, %H:%M"/>
      <property name="digital-time-font" type="string" value="Sans 12"/>
    </property>
    <property name="plugin-9" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="volume-step" type="uint" value="1"/>
      <property name="volume-max" type="uint" value="100"/>
    </property>
    <property name="plugin-11" type="string" value="whiskermenu">
      <property name="recent" type="array">
        <value type="string" value="xfce4-about.desktop"/>
        <value type="string" value="xfce-ui-settings.desktop"/>
        <value type="string" value="xfce-keyboard-settings.desktop"/>
        <value type="string" value="org.xfce.mousepad.desktop"/>
      </property>
      <property name="favorites" type="array">
        <value type="string" value="xfce4-web-browser.desktop"/>
        <value type="string" value="xfce4-file-manager.desktop"/>
        <value type="string" value="xfce4-terminal-emulator.desktop"/>
      </property>
      <property name="show-command-restart" type="bool" value="true"/>
      <property name="show-command-shutdown" type="bool" value="true"/>
      <property name="confirm-session-command" type="bool" value="false"/>
    </property>
    <property name="plugin-1" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17868253773.desktop"/>
      </property>
    </property>
    <property name="plugin-4" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17868253772.desktop"/>
      </property>
    </property>
    <property name="plugin-10" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17868253771.desktop"/>
      </property>
    </property>
    <property name="plugin-12" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-14" type="string" value="systray"/>
  </property>
</channel>
EOF

xfconf-query -c xfwm4 \
  -p /general/use_compositing \
  --create -t bool -s false

xfce4-panel -r

rm -f ~/.config/autostart/xfce4-screensaver.desktop

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/presentation-mode \
  --create -t bool -s true

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/dpms-enabled \
  --create -t bool -s false

xfce4-power-manager --restart

echo "Done. Reboot recommended."
