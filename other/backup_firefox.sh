#!/usr/bin/env bash

set -u

# Firefox profile backup script for Linux.
#
# Supported installation methods:
#   - Distribution packages
#   - Snap
#   - Flatpak
#
# The script:
#   1. Checks whether "zip" is installed.
#   2. Installs "zip" using the detected package manager if necessary.
#   3. Finds Firefox profile directories.
#   4. Uses profiles.ini to identify registered Firefox profiles.
#   5. Creates firefox.zip in the current working directory.
#
# Supported package managers:
#   - apt
#   - dnf
#   - yum
#   - pacman


set -o pipefail


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

OUTPUT_FILE="$(pwd)/firefox.zip"
TEMP_DIR="$(mktemp -d)"


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT


# ------------------------------------------------------------
# Root / sudo handling
# ------------------------------------------------------------

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "ERROR: This operation requires root privileges."
        echo "Please install the 'zip' package manually or run this script as root."
        exit 1
    fi
}


# ------------------------------------------------------------
# Install zip if necessary
# ------------------------------------------------------------

install_zip() {

    if command -v zip >/dev/null 2>&1; then
        echo "zip is already installed."
        return 0
    fi

    echo "The 'zip' command is not installed."
    echo "Attempting to install it..."
    echo

    if command -v apt-get >/dev/null 2>&1; then

        echo "Detected APT-based distribution."

        run_as_root apt-get update
        run_as_root apt-get install -y zip

    elif command -v dnf >/dev/null 2>&1; then

        echo "Detected DNF-based distribution."

        run_as_root dnf install -y zip

    elif command -v yum >/dev/null 2>&1; then

        echo "Detected YUM-based distribution."

        run_as_root yum install -y zip

    elif command -v pacman >/dev/null 2>&1; then

        echo "Detected Pacman-based distribution."

        run_as_root pacman -Sy --noconfirm zip

    else

        echo
        echo "ERROR: Could not detect a supported package manager."
        echo
        echo "Please install the 'zip' package manually and run the script again."
        echo
        echo "Supported package managers:"
        echo "  apt"
        echo "  dnf"
        echo "  yum"
        echo "  pacman"
        exit 1

    fi

    if ! command -v zip >/dev/null 2>&1; then
        echo
        echo "ERROR: The 'zip' command is still unavailable after installation."
        exit 1
    fi

    echo
    echo "zip installation completed."
}


# ------------------------------------------------------------
# Find Firefox profile roots
# ------------------------------------------------------------

declare -a PROFILE_ROOTS=()

add_profile_root() {

    local path="$1"

    if [ -d "$path" ]; then

        for existing in "${PROFILE_ROOTS[@]}"; do
            if [ "$existing" = "$path" ]; then
                return
            fi
        done

        PROFILE_ROOTS+=("$path")
    fi
}


# Standard Firefox installation
add_profile_root "$HOME/.mozilla/firefox"

# Snap Firefox
add_profile_root "$HOME/snap/firefox/common/.mozilla/firefox"

# Flatpak Firefox
add_profile_root "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"


# ------------------------------------------------------------
# Find registered Firefox profiles
# ------------------------------------------------------------

find_registered_profiles() {

    local root="$1"
    local profiles_ini="$root/profiles.ini"

    if [ ! -f "$profiles_ini" ]; then
        return
    fi

    echo "Reading: $profiles_ini"

    # Firefox profiles.ini contains entries such as:
    #
    # [Profile0]
    # Name=default-release
    # IsRelative=1
    # Path=xxxxx.default-release
    #
    # We extract Path and IsRelative pairs.
    #
    # The result is stored in temporary files because profiles.ini
    # may contain several profiles.

    awk '
        /^\[Profile[0-9]+\]/ {
            if (path != "") {
                print relative "|" path
            }
            relative=""
            path=""
        }

        /^IsRelative=/ {
            relative=$0
            sub(/^IsRelative=/, "", relative)
        }

        /^Path=/ {
            path=$0
            sub(/^Path=/, "", path)
        }

        END {
            if (path != "") {
                print relative "|" path
            }
        }
    ' "$profiles_ini" |
    while IFS='|' read -r is_relative profile_path; do

        [ -z "$profile_path" ] && continue

        if [ "$is_relative" = "1" ]; then
            full_path="$root/$profile_path"
        else
            full_path="$profile_path"
        fi

        if [ -d "$full_path" ]; then
            echo "  Profile: $full_path"
            echo "$full_path"
        else
            echo "  WARNING: Profile directory not found: $full_path" >&2
        fi

    done
}


# ------------------------------------------------------------
# Copy profiles
# ------------------------------------------------------------

copy_profiles() {

    local root="$1"
    local installation_name="$2"

    local profiles_ini="$root/profiles.ini"

    if [ ! -f "$profiles_ini" ]; then
        echo
        echo "No profiles.ini found in:"
        echo "  $root"
        return
    fi

    local destination="$TEMP_DIR/$installation_name"

    mkdir -p "$destination"

    echo
    echo "Processing Firefox installation:"
    echo "  $root"
    echo

    # Always preserve profiles.ini.
    cp -a "$profiles_ini" "$destination/"

    # Extract the actual profile paths again without printing
    # diagnostic information.
    awk '
        /^\[Profile[0-9]+\]/ {
            if (path != "") {
                print relative "|" path
            }
            relative=""
            path=""
        }

        /^IsRelative=/ {
            relative=$0
            sub(/^IsRelative=/, "", relative)
        }

        /^Path=/ {
            path=$0
            sub(/^Path=/, "", path)
        }

        END {
            if (path != "") {
                print relative "|" path
            }
        }
    ' "$profiles_ini" |
    while IFS='|' read -r is_relative profile_path; do

        [ -z "$profile_path" ] && continue

        if [ "$is_relative" = "1" ]; then
            full_path="$root/$profile_path"
        else
            full_path="$profile_path"
        fi

        if [ -d "$full_path" ]; then

            # Keep the profile directory name exactly as Firefox uses it.
            profile_name="$(basename "$full_path")"

            echo "Backing up profile:"
            echo "  $full_path"

            cp -a "$full_path" "$destination/"

        else

            echo "WARNING: Skipping missing profile:"
            echo "  $full_path"

        fi

    done
}


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

echo
echo "Firefox Profile Backup"
echo "======================"
echo

echo "Backup destination:"
echo "  $OUTPUT_FILE"
echo

# Make sure zip exists.
install_zip

echo
echo "Searching for Firefox installations..."
echo

if [ "${#PROFILE_ROOTS[@]}" -eq 0 ]; then
    echo "ERROR: No Firefox profile directory was found."
    echo
    echo "Checked:"
    echo "  $HOME/.mozilla/firefox"
    echo "  $HOME/snap/firefox/common/.mozilla/firefox"
    echo "  $HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
    exit 1
fi


# ------------------------------------------------------------
# Backup each installation
# ------------------------------------------------------------

BACKUP_COUNT=0

for root in "${PROFILE_ROOTS[@]}"; do

    case "$root" in

        "$HOME/.mozilla/firefox")
            installation_name="distribution"
            ;;

        "$HOME/snap/firefox/common/.mozilla/firefox")
            installation_name="snap"
            ;;

        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox")
            installation_name="flatpak"
            ;;

        *)
            installation_name="firefox"
            ;;

    esac

    echo "Found Firefox profile root:"
    echo "  $root"

    copy_profiles "$root" "$installation_name"

    BACKUP_COUNT=$((BACKUP_COUNT + 1))

done


# ------------------------------------------------------------
# Check backup contents
# ------------------------------------------------------------

if [ -z "$(find "$TEMP_DIR" -mindepth 1 -print -quit)" ]; then
    echo
    echo "ERROR: No Firefox profiles were found."
    exit 1
fi


# ------------------------------------------------------------
# Create ZIP
# ------------------------------------------------------------

echo
echo "Creating firefox.zip..."

rm -f "$OUTPUT_FILE"

(
    cd "$TEMP_DIR" || exit 1
    zip -r -q "$OUTPUT_FILE" .
)

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Failed to create firefox.zip."
    exit 1
fi


# ------------------------------------------------------------
# Final information
# ------------------------------------------------------------

echo
echo "Backup completed successfully."
echo
echo "Backup file:"
echo "  $OUTPUT_FILE"
echo

du -h "$OUTPUT_FILE" | awk '{print "Backup size: " $1}'

echo
echo "Firefox installations backed up: $BACKUP_COUNT"
echo
