#!/bin/bash

CONFIG="$HOME/.config/niri/cfg/input.kdl"

grep -q 'options "compose:ralt"' "$CONFIG" || \
sed -i '/xkb {/a\            options "compose:ralt"' "$CONFIG"

niri validate && niri msg action load-config-file
