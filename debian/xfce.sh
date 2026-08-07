#!/usr/bin/env bash
set -euo pipefail

sudo sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
    -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' \
    /etc/default/grub

sudo update-grub

sudo systemctl disable --now bluetooth.service 2>/dev/null || true
sudo systemctl disable --now ModemManager.service 2>/dev/null || true

xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true

PANEL_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
PANEL_FILE="$PANEL_DIR/xfce4-panel.xml"

mkdir -p "$PANEL_DIR"

if [ -f "$PANEL_FILE" ]; then
    cp "$PANEL_FILE" "$PANEL_FILE.backup"
fi

xfce4-panel --quit 2>/dev/null || true

cat > "$PANEL_FILE" <<'EOF'
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
      <property name="icon-size" type="uint" value="18"/>
      <property name="size" type="uint" value="32"/>

      <property name="plugin-ids" type="array">
        <value type="int" value="10"/>
        <value type="int" value="12"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="21"/>
        <value type="int" value="22"/>
      </property>
    </property>
  </property>

  <property name="plugins" type="empty">

    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
    </property>

    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-4" type="string" value="pager">
      <property name="rows" type="uint" value="1"/>
    </property>

    <property name="plugin-5" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-6" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>

    <property name="plugin-7" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-8" type="string" value="clock">
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-font" type="string" value="Sans 12"/>
    </property>

    <property name="plugin-9" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="volume-step" type="uint" value="1"/>
      <property name="volume-max" type="uint" value="100"/>
    </property>

    <property name="plugin-10" type="string" value="whiskermenu"/>

    <property name="plugin-21" type="string" value="notification-plugin"/>

    <property name="plugin-22" type="string" value="showdesktop"/>

  </property>

</channel>
EOF

xfce4-panel &
