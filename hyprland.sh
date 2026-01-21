#!/usr/bin/env bash
set -e

echo "==> Hyprland first run setup (Arch Linux with fonts, full binds, Waybar, safe mode)"

# --------------------------------
# Ensure pacman exists (Arch)
# --------------------------------
if ! command -v pacman &>/dev/null; then
    echo "Error: pacman not found. This script is intended for Arch Linux."
    exit 1
fi

# --------------------------------
# Required packages
# --------------------------------
PACKAGES=(
    hyprland
    kitty
    dolphin
    firefox
    spotify-launcher
    playerctl
    pamixer
    pipewire
    pipewire-audio
    pipewire-pulse
    wireplumber
    waybar
    networkmanager
    mako
    xdg-desktop-portal
    xdg-desktop-portal-hyprland

    # Fonts
    ttf-dejavu
    ttf-liberation
    ttf-iosevka
    ttf-fira-code
)

echo "==> Installing required packages..."
# Use nohup to avoid killing terminal if script is closed
nohup sudo pacman -S --needed --noconfirm "${PACKAGES[@]}" >/tmp/hypr_install.log 2>&1 &

# --------------------------------
# Enable NetworkManager (Wi-Fi)
# --------------------------------
sudo systemctl enable --now NetworkManager

# --------------------------------
# System font configuration (fontconfig)
# --------------------------------
echo "==> Setting system default fonts"
FC_DIR="$HOME/.config/fontconfig"
mkdir -p "$FC_DIR"

cat > "$FC_DIR/fonts.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <match target="pattern">
        <test name="family" qual="any">
            <string>sans</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>DejaVu Sans</string>
        </edit>
    </match>

    <match target="pattern">
        <test name="family" qual="any">
            <string>serif</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>DejaVu Serif</string>
        </edit>
    </match>

    <match target="pattern">
        <test name="family" qual="any">
            <string>monospace</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>Iosevka</string>
        </edit>
    </match>
</fontconfig>
EOF

# Update font cache safely in background
nohup fc-cache -fv >/tmp/hypr_fonts.log 2>&1 &

# --------------------------------
# Hyprland config
# --------------------------------
HYPR_DIR="$HOME/.config/hypr"
CONF_FILE="$HYPR_DIR/hyprland.conf"
mkdir -p "$HYPR_DIR"

echo "==> Writing full hyprland.conf"
cat > "$CONF_FILE" << 'EOF'
################
### MONITORS ###
################
monitor=DP-1,1920x1080@239.96,0x0,1

###################
### MY PROGRAMS ###
###################
$terminal = kitty
$fileManager = dolphin
$menu = hyprlauncher

#################
### AUTOSTART ###
#################
exec-once = firefox --new-window
exec-once = waybar

#############################
### ENVIRONMENT VARIABLES ###
#############################
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24

#####################
### LOOK AND FEEL ###
#####################
general {
    gaps_in = 5
    gaps_out = 20
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    resize_on_border = false
    allow_tearing = false
    layout = dwindle
}

decoration {
    rounding = 10
    active_opacity = 1.0
    inactive_opacity = 1.0
    shadow {
        enabled = true
        range = 4
        render_power = 3
        color = rgba(1a1a1aee)
    }
    blur {
        enabled = true
        size = 3
        passes = 1
    }
}

animations {
    enabled = yes
    animation = windows, 1, 4, default
    animation = workspaces, 1, 2, default
}

dwindle {
    pseudotile = true
    preserve_split = true
}

master {
    new_status = master
}

misc {
    force_default_wallpaper = 0
    disable_hyprland_logo = true
}

#############
### INPUT ###
#############
input {
    kb_layout = us
    kb_options = compose:ralt
    follow_mouse = 1
    accel_profile = flat
    sensitivity = 0.0
    touchpad {
        natural_scroll = false
    }
}
gesture = 3, horizontal, workspace

###################
### KEYBINDINGS ###
###################
$mainMod = SUPER
bind = $mainMod, Q, exec, $terminal
bind = $mainMod, C, killactive
bind = $mainMod, M, exec, command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating
bind = $mainMod, R, exec, $menu
bind = $mainMod, P, pseudo
bind = $mainMod, J, togglesplit
bind = $mainMod, B, exec, firefox
bind = $mainMod, S, exec, spotify-launcher

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Multimedia keys
bind = , XF86AudioPlay, exec, playerctl play-pause
bind = , XF86AudioNext, exec, playerctl next
bind = , XF86AudioPrev, exec, playerctl previous
bind = , XF86AudioMute, exec, pamixer -t
bind = , XF86AudioRaiseVolume, exec, pamixer --no-boost -i 1
bind = , XF86AudioLowerVolume, exec, pamixer --no-boost -d 1

# Switch workspaces with mainMod + [0-9]
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to a workspace with mainMod + SHIFT + [0-9]
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

##############################
### WINDOWS AND WORKSPACES ###
##############################
windowrulev2 = suppress_event maximize, class:.*
windowrulev2 = nofocus, xwayland:1, floating:1
EOF

# --------------------------------
# Waybar configuration
# --------------------------------
WAYBAR_DIR="$HOME/.config/waybar"
mkdir -p "$WAYBAR_DIR"

cat > "$WAYBAR_DIR/config.jsonc" << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 28,

    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network"],

    "hyprland/workspaces": {
        "disable-scroll": true,
        "format": "{name}"
    },

    "pulseaudio": {
        "format": " {volume}%",
        "format-muted": "󰖁 muted"
    },

    "network": {
        "format-wifi": "",
        "format-disconnected": "󰤭"
    },

    "clock": {
        "format": "{:%Y-%m-%d  %H:%M}"
    }
}
EOF

cat > "$WAYBAR_DIR/style.css" << 'EOF'
* {
    font-family: "Iosevka", monospace;
    font-size: 13px;
    padding: 0 6px;
}

window#waybar {
    background: rgba(20, 20, 20, 0.85);
    color: #ffffff;
}

#workspaces button.active {
    background: #33ccff;
    color: #000000;
}

#clock, #pulseaudio, #network {
    padding: 0 10px;
}
EOF

echo "==> Setup complete"
echo "==> Log out and back in to Hyprland"
