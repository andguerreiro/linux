
#!/bin/bash

CONFIG="$HOME/.config/niri/cfg/input.kdl"

sed -i '/xkb {/a\            compose "ralt"' "$CONFIG"

niri msg action load-config-file
