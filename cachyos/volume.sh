#!/bin/bash

CONFIG="$HOME/.config/niri/cfg/keybinds.kdl"

sed -i \
    -e 's/noctalia msg volume-up/noctalia msg volume-up 1/g' \
    -e 's/noctalia msg volume-down/noctalia msg volume-down 1/g' \
    "$CONFIG"

niri validate && niri msg action load-config-file
