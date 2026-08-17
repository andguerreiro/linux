#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Gentoo Install Script v4
#
# Ryzen 7 5700X + Radeon RX 7600
# UEFI + OpenRC + XFCE + LightDM
# NetworkManager + PipeWire + GRUB
#
# WARNING: THIS ERASES /dev/nvme0n1
# ============================================================

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"
TARGET="/mnt/gentoo"

HOSTNAME="gentoo"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

CFLAGS="-O2 -pipe -march=znver3"
MAKEOPTS="-j16"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Checks
# ------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Run this as root."
[[ -d /sys/firmware/efi ]] || die "Booted without UEFI."
[[ -b "$DISK" ]] || die "Disk not found: $DISK"

clear

echo "============================================================"
echo "             GENTOO V4 INSTALLER"
echo "============================================================"
echo
echo "CPU : Ryzen 7 5700X"
echo "GPU : Radeon RX 7600"
echo
echo "DISK: $DISK"
echo
echo "ALL DATA ON THIS DISK WILL BE ERASED."
echo
lsblk "$DISK"
echo

read -r -p "Type YES to continue: " ANSWER
[[ "$ANSWER" == "YES" ]] || die "Cancelled."

# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

read -r -s -p "Password for $USERNAME and root: " PASSWORD
echo
read -r -s -p "Confirm password: " PASSWORD2
echo

[[ "$PASSWORD" == "$PASSWORD2" ]] || die "Passwords do not match."
[[ -n "$PASSWORD" ]] || die "Password cannot be empty."

unset PASSWORD2

# ------------------------------------------------------------
# Internet
# ------------------------------------------------------------

msg "CHECKING INTERNET"

wget -q --spider --timeout=15 \
    https://distfiles.gentoo.org/ ||
    die "No internet connection."

# ------------------------------------------------------------
# Disk
# ------------------------------------------------------------

msg "PARTITIONING DISK"

swapoff -a 2>/dev/null || true
umount -R "$TARGET" 2>/dev/null || true

wipefs -af "$DISK"
sgdisk --zap-all "$DISK"

sgdisk \
    --clear \
    --new=1:2048:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "$DISK"

partprobe "$DISK"
udevadm settle
sleep 2

[[ -b "$EFI" ]] || die "EFI partition missing."
[[ -b "$ROOT" ]] || die "Root partition missing."

# ------------------------------------------------------------
# Filesystems
# ------------------------------------------------------------

msg "FORMATTING"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

# ------------------------------------------------------------
# Mount
# ------------------------------------------------------------

msg "MOUNTING"

mkdir -p "$TARGET"

mount "$ROOT" "$TARGET"

mkdir -p "$TARGET/efi"
mount "$EFI" "$TARGET/efi"

# ------------------------------------------------------------
# Stage 3
# ------------------------------------------------------------

msg "DOWNLOADING GENTOO DESKTOP STAGE 3"

STAGE_FILE="$(
    wget -qO- \
    "$STAGE_BASE/latest-stage3-amd64-desktop-openrc.txt" |
    awk '$1 ~ /^stage3-amd64-desktop-openrc-.*\.tar\.xz$/ {
        print $1
        exit
    }'
)"

[[ -n "$STAGE_FILE" ]] || die "Could not find Stage 3."

echo "Using: $STAGE_FILE"

mkdir -p "$TARGET/var/tmp"
cd "$TARGET/var/tmp"

wget -c "$STAGE_BASE/$STAGE_FILE"
wget -c "$STAGE_BASE/$STAGE_FILE.sha256"

msg "VERIFYING STAGE 3"

sha256sum -c "$STAGE_FILE.sha256"

msg "EXTRACTING STAGE 3"

tar xpf "$STAGE_FILE" \
    --xattrs-include='*.*' \
    --numeric-owner \
    -C "$TARGET"

rm -f "$STAGE_FILE" "$STAGE_FILE.sha256"

# ------------------------------------------------------------
# DNS + fstab
# ------------------------------------------------------------

msg "CONFIGURING FILESYSTEMS"

rm -f "$TARGET/etc/resolv.conf"
cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"
EFI_UUID="$(blkid -s UUID -o value "$EFI")"

cat > "$TARGET/etc/fstab" <<EOF
UUID=$ROOT_UUID  /      ext4  noatime,errors=remount-ro  0 1
UUID=$EFI_UUID   /efi   vfat  umask=0077                0 2
EOF

# ------------------------------------------------------------
# Gentoo repository
# ------------------------------------------------------------

mkdir -p "$TARGET/etc/portage/repos.conf"

cat > "$TARGET/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-jobs = 1
EOF

# ------------------------------------------------------------
# Chroot mounts
# ------------------------------------------------------------

msg "PREPARING CHROOT"

mount --types proc /proc "$TARGET/proc"

mount --rbind /sys "$TARGET/sys"
mount --make-rslave "$TARGET/sys"

mount --rbind /dev "$TARGET/dev"
mount --make-rslave "$TARGET/dev"

mount --rbind /run "$TARGET/run"
mount --make-rslave "$TARGET/run"

# ------------------------------------------------------------
# Pass settings to chroot
# ------------------------------------------------------------

export GENTOO_HOSTNAME="$HOSTNAME"
export GENTOO_USERNAME="$USERNAME"
export GENTOO_PASSWORD="$PASSWORD"
export GENTOO_TIMEZONE="$TIMEZONE"
export GENTOO_LOCALE="$LOCALE"
export GENTOO_KEYMAP="$KEYMAP"
export GENTOO_CFLAGS="$CFLAGS"
export GENTOO_MAKEOPTS="$MAKEOPTS"

unset PASSWORD

# ------------------------------------------------------------
# Chroot installation
# ------------------------------------------------------------

msg "INSTALLING GENTOO"

cat > "$TARGET/root/install.sh" <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail

HOSTNAME="$GENTOO_HOSTNAME"
USERNAME="$GENTOO_USERNAME"
PASSWORD="$GENTOO_PASSWORD"
TIMEZONE="$GENTOO_TIMEZONE"
LOCALE="$GENTOO_LOCALE"
KEYMAP="$GENTOO_KEYMAP"
CFLAGS="$GENTOO_CFLAGS"
MAKEOPTS="$GENTOO_MAKEOPTS"

# ------------------------------------------------------------
# Portage
# ------------------------------------------------------------

echo "Syncing Gentoo repository..."

emerge --sync || emerge-webrsync

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="$CFLAGS"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="$MAKEOPTS"

VIDEO_CARDS="amdgpu radeonsi"
GRUB_PLATFORMS="efi-64"

USE="X wayland elogind pipewire sound-server -systemd"

L10N="en-US"
LINGUAS="en"

ACCEPT_LICENSE="@FREE @BINARY-REDISTRIBUTABLE"
EOF

# Gentoo binary packages.
mkdir -p /etc/portage/binrepos.conf

cat > /etc/portage/binrepos.conf/gentoo.conf <<'EOF'
[gentoobinhost]
priority = 1
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
EOF

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
EOF

locale-gen
eselect locale set en_US.utf8

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# ------------------------------------------------------------
# Keyboard + hostname
# ------------------------------------------------------------

echo "keymap=\"$KEYMAP\"" > /etc/conf.d/keymaps

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       $HOSTNAME.localdomain $HOSTNAME
EOF

# ------------------------------------------------------------
# Desktop
# ------------------------------------------------------------

echo "Installing kernel, XFCE, LightDM and services..."

emerge --ask=n --usepkg \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    sys-boot/grub \
    sys-boot/efibootmgr \
    xfce-base/xfce4-meta \
    x11-terms/xfce4-terminal \
    x11-misc/lightdm \
    x11-misc/lightdm-gtk-greeter \
    gui-libs/display-manager-init \
    net-misc/networkmanager \
    sys-apps/dbus \
    sys-auth/elogind \
    media-video/pipewire \
    media-video/wireplumber \
    app-admin/sudo \
    app-editors/nano \
    app-portage/gentoolkit \
    sys-apps/pciutils \
    sys-apps/usbutils \
    sys-process/htop

# ------------------------------------------------------------
# OpenRC services
# ------------------------------------------------------------

rc-update del dhcpcd default 2>/dev/null || true

rc-update add NetworkManager default
rc-update add dbus default
rc-update add elogind boot

cat > /etc/conf.d/display-manager <<'EOF'
CHECKVT=7
DISPLAYMANAGER="lightdm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# User
# ------------------------------------------------------------

groupadd -f plugdev

useradd \
    -m \
    -s /bin/bash \
    -G wheel,audio,video,input,plugdev \
    "$USERNAME"

echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

echo "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

rm -f /root/install.sh

echo
echo "============================================================"
echo " CHROOT INSTALLATION COMPLETE"
echo "============================================================"
CHROOT

chmod 700 "$TARGET/root/install.sh"

chroot "$TARGET" /bin/bash -c '
    export HOME=/root
    export TERM="${TERM:-xterm}"
    /root/install.sh
'

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "CLEANING UP"

rm -f "$TARGET/root/install.sh"

sync
umount -R "$TARGET"

echo
echo "============================================================"
echo "        GENTOO INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "CPU        : Ryzen 7 5700X"
echo "GPU        : Radeon RX 7600"
echo "Desktop    : XFCE"
echo "Login      : LightDM"
echo "Network    : NetworkManager"
echo "Audio      : PipeWire"
echo "Init       : OpenRC"
echo "Bootloader : GRUB UEFI"
echo
echo "Remove the installation media and reboot."
echo
echo "============================================================"
