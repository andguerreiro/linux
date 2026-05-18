#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
CONF_FILE="$CONF_DIR/custom-rates.conf"

mkdir -p "$CONF_DIR"

cat > "$CONF_FILE" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo "PipeWire sample rates configured."
