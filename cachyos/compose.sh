#!/bin/bash

CONFIG="$HOME/.config/niri/cfg/input.kdl"

sed -i 's/compose "ralt"/options "compose:ralt"/' "$CONFIG"

niri msg action load-config-file
