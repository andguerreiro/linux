#!/bin/bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="/usr/share/ollama/.ollama/models/"
DESTINATION="$SCRIPT_DIR/models/"

mkdir -p "$DESTINATION"

sudo rsync -rltv --info=progress2 "$SOURCE" "$DESTINATION"

echo
echo "Ollama models copied successfully to:"
echo "$DESTINATION"
