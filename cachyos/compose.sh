#!/bin/bash

CONFIG="$HOME/.config/niri/cfg/input.kdl"

sed -i '/xkb {/a\            options "compose:ralt"' "$CONFIG"

niri validate && niri msg action load-config-file
