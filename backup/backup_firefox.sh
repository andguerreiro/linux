#!/usr/bin/env bash

set -euo pipefail

# Directory where the script was executed
DESTINATION="$(pwd)"

# Possible Firefox profile directories
FIREFOX_DIRS=(
    "$HOME/.config/mozilla/firefox"
    "$HOME/snap/firefox/common/.mozilla/firefox"
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
)

# Find available Firefox profile directories
PROFILE_DIRS=()

for firefox_dir in "${FIREFOX_DIRS[@]}"; do
    if [[ -d "$firefox_dir" ]]; then
        while IFS= read -r profile; do
            PROFILE_DIRS+=("$profile")
        done < <(
            find "$firefox_dir" \
                -mindepth 1 \
                -maxdepth 1 \
                -type d \
                -name "*.default*" \
                -print
        )
    fi
done

if [[ ${#PROFILE_DIRS[@]} -eq 0 ]]; then
    echo "Error: no Firefox profile found."
    echo
    echo "Searched:"
    for dir in "${FIREFOX_DIRS[@]}"; do
        echo "  $dir"
    done
    exit 1
fi

# Try to identify the currently active profile using Firefox lock files
CURRENT_PROFILE=""

for profile in "${PROFILE_DIRS[@]}"; do
    if [[ -e "$profile/.parentlock" || -e "$profile/lock" ]]; then
        CURRENT_PROFILE="$profile"
        break
    fi
done

# If no active profile was detected, use the first profile found
if [[ -z "$CURRENT_PROFILE" ]]; then
    CURRENT_PROFILE="${PROFILE_DIRS[0]}"
fi

# Archive filename: firefox-YEARMMDD.tar.gz
DATE="$(date '+%Y%m%d')"
ARCHIVE="$DESTINATION/firefox-${DATE}.tar.gz"

echo "Firefox profile:"
echo "  $CURRENT_PROFILE"
echo
echo "Creating backup:"
echo "  $ARCHIVE"
echo

# Compress the contents of the profile directory
tar -czf "$ARCHIVE" -C "$CURRENT_PROFILE" .

echo
echo "Backup completed successfully."
echo
echo "Archive:"
echo "  $ARCHIVE"
echo
echo "Size:"
du -h "$ARCHIVE" | cut -f1
