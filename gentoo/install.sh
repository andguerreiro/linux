```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Gentoo Automated Installer
#
# Target hardware:
#   AMD Ryzen 7 5700X
#   AMD Radeon RX 7600
#   Kingston KC3000 512 GB NVMe
#   16 GB RAM
#
# Installation:
#   UEFI
#   GPT
#   1 GiB EFI System Partition
#   Remaining space: ext4 /
#   amd64 nomultilib
#   OpenRC
#   KDE Plasma 6
#   SDDM
#   NetworkManager
#   PipeWire + WirePlumber
#   gentoo-kernel-bin
#   dracut initramfs
#   GRUB
#   8 GiB zram swap
#
# WARNING:
#   /dev/nvme0n1 WILL BE COMPLETELY ERASED.
#
# ============================================================

set +u
source /etc/profile
set -u

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

TARGET="/mnt/gentoo"

HOSTNAME="gentoo"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# Ryzen 7 5700X = Zen 3
CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"

# 16 GiB RAM
MAKEOPTS="-j8"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] || \
    die "The LiveGUI was not booted in UEFI mode."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

command -v sgdisk >/dev/null 2>&1 || \
    die "sgdisk is not available."

command -v mkfs.fat >/dev/null 2>&1 || \
    die "mkfs.fat is not available."

command -v wget >/dev/null 2>&1 || \
    die "wget is not available."

command -v sha256sum >/dev/null 2>&1 || \
    die "sha256sum is not available."

command -v chroot >/dev/null 2>&1 || \
    die "chroot is not available."

# ------------------------------------------------------------
# Detect target disk
# ------------------------------------------------------------

DISK_TYPE="$(lsblk -dn -o TYPE "${DISK}" | tr -d ' ')"
MODEL="$(lsblk -dn -o MODEL "${DISK}" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "${DISK}")"

[[ "${DISK_TYPE}" == "disk" ]] || \
    die "${DISK} does not appear to be a physical disk."

# ------------------------------------------------------------
# Safety confirmation
# ------------------------------------------------------------

clear

echo "============================================================"
echo "              GENTOO AUTOMATED INSTALLER"
echo "============================================================"
echo
echo "TARGET DISK"
echo
echo "  Device : ${DISK}"
echo "  Model  : ${MODEL}"
echo "  Size   : ${SIZE}"
echo
echo "THE FOLLOWING PARTITION TABLE WILL BE CREATED:"
echo
echo "  ${EFI}    1 GiB       EFI System Partition"
echo "  ${ROOT}   remaining   ext4 root filesystem"
echo
echo "SYSTEM CONFIGURATION:"
echo
echo "  CPU        : AMD Ryzen 7 5700X"
echo "  GPU        : AMD Radeon RX 7600"
echo "  Init       : OpenRC"
echo "  Desktop    : KDE Plasma 6"
echo "  Login      : SDDM"
echo "  Kernel     : gentoo-kernel-bin"
echo "  Initramfs  : dracut"
echo "  Bootloader : GRUB UEFI"
echo "  Multilib   : disabled"
echo "  Swap       : 8 GiB zram"
echo "  Hostname   : ${HOSTNAME}"
echo "  User       : ${USERNAME}"
echo "  Locale     : ${LOCALE}"
echo "  Keyboard   : ${KEYMAP}"
echo "  Timezone   : ${TIMEZONE}"
echo
echo "============================================================"
echo
echo "ALL DATA ON ${DISK} WILL BE DESTROYED."
echo
echo "The Ventoy USB drive (/dev/sda) will NOT be touched."
echo
echo "Current disks:"
echo
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS
echo
echo "============================================================"
echo

read -r -p "Type APAGAR to continue: " CONFIRM

[[ "${CONFIRM}" == "APAGAR" ]] || \
    die "Installation cancelled."

# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

echo
echo "Set the initial password for user '${USERNAME}'."
echo "You may use the password you previously chose."
echo

read -r -s -p "Password: " USER_PASSWORD
echo

read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo

[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] || \
    die "Passwords do not match."

[[ -n "${USER_PASSWORD}" ]] || \
    die "Password cannot be empty."

# ------------------------------------------------------------
# Network check
# ------------------------------------------------------------

msg "CHECKING INTERNET CONNECTION"

ping -c 3 -W 5 distfiles.gentoo.org >/dev/null 2>&1 || \
    die "Internet connection is not working."

echo "Internet connection OK."

# ------------------------------------------------------------
# Disable existing swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true

# ------------------------------------------------------------
# Unmount old target partitions
# ------------------------------------------------------------

msg "UNMOUNTING OLD TARGET PARTITIONS"

umount "${DISK}"* 2>/dev/null || true

# ------------------------------------------------------------
# Erase existing partition table
# ------------------------------------------------------------

msg "ERASING EXISTING PARTITION TABLE"

wipefs -a "${DISK}"
sgdisk --zap-all "${DISK}"

# ------------------------------------------------------------
# Create GPT partition table
# ------------------------------------------------------------

msg "CREATING GPT PARTITION TABLE"

sgdisk \
    --clear \
    --new=1:0:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "${DISK}"

partprobe "${DISK}"
sleep 3

[[ -b "${EFI}" ]] || \
    die "EFI partition was not created."

[[ -b "${ROOT}" ]] || \
    die "Root partition was not created."

# ------------------------------------------------------------
# Format filesystems
# ------------------------------------------------------------

msg "FORMATTING EFI PARTITION"

mkfs.fat -F 32 -n EFI "${EFI}"

msg "FORMATTING ROOT PARTITION"

mkfs.ext4 -F -L gentoo-root "${ROOT}"

# ------------------------------------------------------------
# Mount target
# ------------------------------------------------------------

msg "MOUNTING TARGET FILESYSTEM"

mkdir -p "${TARGET}"

mount "${ROOT}" "${TARGET}"

mkdir -p "${TARGET}/efi"

mount "${EFI}" "${TARGET}/efi"

# ------------------------------------------------------------
# Download Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 NOMULTILIB OPENRC STAGE 3"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-nomultilib-openrc"

STAGE_FILE="$(
    wget -qO- \
        "${STAGE_BASE}/latest-stage3-amd64-nomultilib-openrc.txt" |
    awk '
        !/^#/ &&
        /stage3-amd64-nomultilib-openrc-.*\.tar\.xz$/ {
            print $1
            exit
        }
    '
)"

[[ -n "${STAGE_FILE}" ]] || \
    die "Could not determine the latest Stage 3 archive."

echo
echo "Selected Stage 3:"
echo "  ${STAGE_FILE}"
echo

cd "${TARGET}"

wget -c "${STAGE_BASE}/${STAGE_FILE}"
wget -c "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

sha256sum -c "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

tar xpvf "${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${STAGE_FILE}" \
    "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

cp --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"

# ------------------------------------------------------------
# Generate fstab
# ------------------------------------------------------------

msg "GENERATING FSTAB"

ROOT_UUID="$(blkid -s UUID -o value "${ROOT}")"
EFI_UUID="$(blkid -s UUID -o value "${EFI}")"

cat > "${TARGET}/etc/fstab" <<EOF
# Gentoo root filesystem
UUID=${ROOT_UUID}    /       ext4    noatime,errors=remount-ro    0 1

# EFI System Partition
UUID=${EFI_UUID}     /efi    vfat    umask=0077                0 2
EOF

# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

mount --types proc /proc "${TARGET}/proc"

mount --rbind /sys "${TARGET}/sys"
mount --make-rslave "${TARGET}/sys"

mount --rbind /dev "${TARGET}/dev"
mount --make-rslave "${TARGET}/dev"

mount --rbind /run "${TARGET}/run"
mount --make-rslave "${TARGET}/run"

cp --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"

# ------------------------------------------------------------
# Export installation variables
# ------------------------------------------------------------

export GENTOO_HOSTNAME="${HOSTNAME}"
export GENTOO_USERNAME="${USERNAME}"
export GENTOO_PASSWORD="${USER_PASSWORD}"
export GENTOO_TIMEZONE="${TIMEZONE}"
export GENTOO_LOCALE="${LOCALE}"
export GENTOO_KEYMAP="${KEYMAP}"
export GENTOO_CFLAGS="${CFLAGS}"
export GENTOO_CXXFLAGS="${CXXFLAGS}"
export GENTOO_MAKEOPTS="${MAKEOPTS}"

# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

HOSTNAME="${GENTOO_HOSTNAME}"
USERNAME="${GENTOO_USERNAME}"
USER_PASSWORD="${GENTOO_PASSWORD}"

TIMEZONE="${GENTOO_TIMEZONE}"
LOCALE="${GENTOO_LOCALE}"
KEYMAP="${GENTOO_KEYMAP}"

CFLAGS="${GENTOO_CFLAGS}"
CXXFLAGS="${GENTOO_CXXFLAGS}"
MAKEOPTS="${GENTOO_MAKEOPTS}"

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Portage configuration
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p /etc/portage
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="${CXXFLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

GRUB_PLATFORMS="efi-64"

L10N="en-US"
LINGUAS="en"

# Keep the system amd64-only.
ABI_X86="64"

# Allow free software and redistributable binary firmware.
ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# Kernel installation configuration
#
# gentoo-kernel-bin expects an initramfs.
# Dracut generates it.
# The grub USE flag makes installkernel update GRUB
# when kernels are installed or upgraded.
# ------------------------------------------------------------

msg "CONFIGURING KERNEL INSTALLATION"

cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut grub
EOF

emerge --ask=n \
    sys-kernel/installkernel

# ------------------------------------------------------------
# Synchronize Gentoo repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync

# ------------------------------------------------------------
# Verify the Stage 3 profile
# ------------------------------------------------------------

msg "VERIFYING GENTOO PROFILE"

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile || true)"

echo
echo "Current profile:"
echo "  ${CURRENT_PROFILE}"
echo

if [[ "${CURRENT_PROFILE}" != *"nomultilib"* ]]; then
    die "The installed Stage 3 is not using a nomultilib profile."
fi

if [[ "${CURRENT_PROFILE}" != *"openrc"* ]]; then
    die "The installed Stage 3 is not using an OpenRC profile."
fi

# ------------------------------------------------------------
# License for linux-firmware
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<EOF
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# KDE Plasma configuration
# ------------------------------------------------------------

msg "CONFIGURING KDE PLASMA"

cat > /etc/portage/package.use/plasma <<EOF
# KDE Plasma
kde-plasma/plasma-meta sddm xwayland gtk

# NetworkManager
net-misc/networkmanager wifi

# PipeWire
media-video/pipewire sound-server pipewire-alsa pipewire-pulse

# WirePlumber
media-video/wireplumber

# AMD firmware
sys-kernel/linux-firmware redistributable
EOF

# ------------------------------------------------------------
# Update base system
# ------------------------------------------------------------

msg "UPDATING BASE SYSTEM"

emerge --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
    @world

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

msg "CONFIGURING LOCALE"

cat > /etc/locale.gen <<EOF
en_US.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

msg "CONFIGURING TIMEZONE"

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

echo "${TIMEZONE}" > /etc/timezone

# ------------------------------------------------------------
# Keyboard
# ------------------------------------------------------------

msg "CONFIGURING KEYBOARD"

cat > /etc/conf.d/keymaps <<EOF
keymap="${KEYMAP}"
EOF

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

msg "CONFIGURING HOSTNAME"

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Install kernel, firmware and initramfs tools
# ------------------------------------------------------------

msg "INSTALLING KERNEL AND FIRMWARE"

emerge --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

# ------------------------------------------------------------
# Install KDE Plasma and desktop stack
# ------------------------------------------------------------

msg "INSTALLING KDE PLASMA"

emerge --ask=n \
    kde-plasma/plasma-meta

# ------------------------------------------------------------
# Install additional desktop packages
# ------------------------------------------------------------

msg "INSTALLING DESKTOP UTILITIES"

emerge --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark \
    app-editors/nano

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "CONFIGURING NETWORKMANAGER"

emerge --ask=n \
    net-misc/networkmanager

rc-update add NetworkManager default

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

msg "CONFIGURING D-BUS"

emerge --ask=n \
    sys-apps/dbus

rc-update add dbus default

# ------------------------------------------------------------
# elogind
# ------------------------------------------------------------

msg "CONFIGURING ELOGIND"

emerge --ask=n \
    sys-auth/elogind

rc-update add elogind boot

# ------------------------------------------------------------
# Display manager
# ------------------------------------------------------------

msg "CONFIGURING SDDM"

emerge --ask=n \
    gui-libs/display-manager-init \
    x11-misc/sddm

cat > /etc/conf.d/display-manager <<EOF
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# Audio
# ------------------------------------------------------------

msg "CONFIGURING PIPEWIRE AUDIO"

emerge --ask=n \
    media-video/pipewire \
    media-sound/wireplumber

# PipeWire and WirePlumber run as user services.
# No system-wide OpenRC service is required.
# ------------------------------------------------------------

# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURING AMD GPU"

mkdir -p /etc/modprobe.d

cat > /etc/modprobe.d/amdgpu.conf <<EOF
# AMD Radeon RX 7600
options amdgpu dc=1
EOF

# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

msg "CONFIGURING ZRAM SWAP"

cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run

description="Compressed zram swap"

depend() {
    need localmount
    after bootmisc
}

start_pre() {
    modprobe zram num_devices=1

    if [[ ! -b /dev/zram0 ]]; then
        return 1
    fi

    zramctl --reset /dev/zram0 2>/dev/null || true

    zramctl \
        --algorithm zstd \
        --size 8G \
        /dev/zram0

    mkswap -L zram0 /dev/zram0 >/dev/null
}

start() {
    ebegin "Enabling zram swap"
    swapon --priority 100 /dev/zram0
    eend $?
}

stop() {
    ebegin "Disabling zram swap"

    swapoff /dev/zram0 2>/dev/null || true
    zramctl --reset /dev/zram0 2>/dev/null || true

    eend 0
}
EOF

chmod +x /etc/init.d/zram-swap

rc-update add zram-swap default

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

msg "INSTALLING GRUB"

emerge --ask=n \
    sys-boot/grub

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"
fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Set the same initial password for root.
echo "root:${USER_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

msg "CONFIGURING SUDO"

emerge --ask=n \
    app-admin/sudo

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

visudo -c

# ------------------------------------------------------------
# Useful Gentoo administration tools
# ------------------------------------------------------------

msg "INSTALLING GENTOO ADMINISTRATION TOOLS"

emerge --ask=n \
    app-portage/gentoolkit \
    app-portage/eix

# ------------------------------------------------------------
# Final world update
# ------------------------------------------------------------

msg "RUNNING FINAL SYSTEM UPDATE"

emerge --ask=n \
    --update \
    --deep \
    --newuse \
    @world

# ------------------------------------------------------------
# Regenerate GRUB after final kernel/package changes
# ------------------------------------------------------------

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Verify kernel and initramfs
# ------------------------------------------------------------

msg "VERIFYING KERNEL AND INITRAMFS"

echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

echo
echo "Initramfs images:"
ls -lh /boot/initramfs-* 2>/dev/null || true

KERNEL_COUNT="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*' | wc -l)"
INITRAMFS_COUNT="$(find /boot -maxdepth 1 -type f -name 'initramfs-*' | wc -l)"

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image was found in /boot."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was found in /boot."

# ------------------------------------------------------------
# Verify GRUB configuration
# ------------------------------------------------------------

msg "VERIFYING GRUB"

[[ -f /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not appear to contain a Linux entry."

# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

echo
echo "Enabled services:"
rc-update show

# ------------------------------------------------------------
# Final information
# ------------------------------------------------------------

msg "FINAL INSTALLATION CHECK"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo
echo "Kernel:"
ls -lh /boot/vmlinuz-* 2>/dev/null

echo
echo "Initramfs:"
ls -lh /boot/initramfs-* 2>/dev/null

echo
echo "EFI files:"
find /efi/EFI -maxdepth 3 -type f 2>/dev/null || true

echo
echo "User:"
id "${USERNAME}"

echo
echo "Root filesystem:"
df -h /

echo
echo "ZRAM:"
zramctl 2>/dev/null || true

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname  : ${HOSTNAME}"
echo "User      : ${USERNAME}"
echo "Desktop   : KDE Plasma"
echo "Login     : SDDM"
echo "Init      : OpenRC"
echo "Kernel    : gentoo-kernel-bin"
echo "Initramfs : dracut"
echo "GPU       : AMD Radeon RX 7600"
echo "Multilib  : disabled"
echo "Swap      : 8 GiB zram"
echo
echo "The initial password was the password entered during setup."
echo
echo "You can change it later with:"
echo
echo "    passwd"
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove installer and sensitive environment variables
# ------------------------------------------------------------

unset USER_PASSWORD
unset GENTOO_PASSWORD

rm -f /root/install-inside-gentoo.sh

exit 0
CHROOT_SCRIPT

chmod +x "${TARGET}/root/install-inside-gentoo.sh"

# ------------------------------------------------------------
# Run chroot installer
# ------------------------------------------------------------

msg "STARTING GENTOO INSTALLATION"

chroot "${TARGET}" /bin/bash -c '
    source /etc/profile
    export PS1="(gentoo) ${PS1:-\\u@\\h \\w\\$ }"
    /root/install-inside-gentoo.sh
'

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "FINAL CLEANUP"

rm -f "${TARGET}/root/install-inside-gentoo.sh"

sync

echo
echo "============================================================"
echo "          GENTOO INSTALLATION FINISHED"
echo "============================================================"
echo
echo "The system has been installed on:"
echo
echo "    ${DISK}"
echo
echo "Next steps:"
echo
echo "    umount -R ${TARGET}"
echo "    sync"
echo "    reboot"
echo
echo "Remove the LiveGUI USB drive when the machine restarts."
echo
echo "============================================================"
```
