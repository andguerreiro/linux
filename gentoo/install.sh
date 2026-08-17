#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Gentoo AMD64 + KDE Plasma + OpenRC
# AMD Ryzen / Radeon
# Gentoo 23.0
# Multilib
# ============================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || {
    echo "ERROR: execute as root."
    exit 1
}

[[ -d /sys ]] || {
    echo "ERROR: /sys is not mounted."
    exit 1
}

[[ -d /proc ]] || {
    echo "ERROR: /proc is not mounted."
    exit 1
}

[[ -d /dev ]] || {
    echo "ERROR: /dev is not mounted."
    exit 1
}

[[ -d /run ]] || {
    echo "ERROR: /run is not mounted."
    exit 1
}

[[ -d /efi ]] || {
    echo "ERROR: /efi does not exist."
    exit 1
}

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

HOSTNAME="gentoo"
USERNAME="gentoo"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="br-abnt2"

CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"
MAKEOPTS="-j8"

ABI_X86="64 32"

PROFILE="default/linux/amd64/23.0/desktop/plasma"

VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

GRUB_PLATFORMS="efi-64"

L10N="en-US"
LINGUAS="en"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
    echo
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Passwords
# ------------------------------------------------------------

msg "CONFIGURATION"

echo "Hostname: ${HOSTNAME}"
echo "Username: ${USERNAME}"
echo "Timezone: ${TIMEZONE}"
echo "Profile: ${PROFILE}"
echo "CFLAGS: ${CFLAGS}"
echo "MAKEOPTS: ${MAKEOPTS}"
echo "ABI_X86: ${ABI_X86}"
echo

read -r -s -p "Senha do usuário ${USERNAME}: " USER_PASSWORD
echo

read -r -s -p "Confirme a senha do usuário ${USERNAME}: " USER_PASSWORD_CONFIRM
echo

[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] || \
    die "Passwords do not match."

read -r -s -p "Senha do root: " ROOT_PASSWORD
echo

read -r -s -p "Confirme a senha do root: " ROOT_PASSWORD_CONFIRM
echo

[[ "${ROOT_PASSWORD}" == "${ROOT_PASSWORD_CONFIRM}" ]] || \
    die "Root passwords do not match."

# ------------------------------------------------------------
# Verify EFI
# ------------------------------------------------------------

msg "VERIFYING EFI"

if [[ ! -d /sys/firmware/efi ]]; then
    die "System was not booted in UEFI mode."
fi

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    die "EFI variables are not mounted."
fi

mountpoint -q /efi || {
    die "/efi is not mounted."
}

echo "UEFI: OK"
echo "/efi: OK"
echo "EFI variables: OK"

# ------------------------------------------------------------
# Portage directories
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p /etc/portage
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license
mkdir -p /etc/portage/repos.conf

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

ABI_X86="${ABI_X86}"

VIDEO_CARDS="${VIDEO_CARDS}"

INPUT_DEVICES="${INPUT_DEVICES}"

GRUB_PLATFORMS="${GRUB_PLATFORMS}"

L10N="${L10N}"
LINGUAS="${LINGUAS}"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# Package USE flags
# ------------------------------------------------------------

cat > /etc/portage/package.use/desktop <<'EOF'
media-video/pipewire sound-server
media-video/wireplumber pipewire
net-misc/networkmanager elogind
x11-misc/sddm wayland
EOF

# ------------------------------------------------------------
# Firmware license
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# Verify repository
# ------------------------------------------------------------

msg "VERIFYING GENTOO REPOSITORY"

[[ -d /var/db/repos/gentoo ]] || \
    die "Gentoo repository does not exist."

# ------------------------------------------------------------
# Synchronize repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync

# ------------------------------------------------------------
# Select Plasma profile
# ------------------------------------------------------------

msg "SELECTING GENTOO PLASMA PROFILE"

PROFILE_PATH="/var/db/repos/gentoo/profiles/${PROFILE}"

[[ -d "${PROFILE_PATH}" ]] || {
    echo
    echo "Available profiles:"
    eselect profile list
    die "Profile does not exist: ${PROFILE}"
}

ln -sfn \
    "${PROFILE_PATH}" \
    /etc/portage/make.profile

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo "Selected profile:"
echo "${CURRENT_PROFILE}"

[[ "${CURRENT_PROFILE}" == "${PROFILE_PATH}" ]] || \
    die "Could not select Plasma profile."

# ------------------------------------------------------------
# Verify ABI
# ------------------------------------------------------------

msg "VERIFYING MULTILIB"

ABI_X86_CURRENT="$(
    emerge --info |
    sed -n 's/.*ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_CURRENT}"

echo "${ABI_X86_CURRENT}" | grep -qw "64" || \
    die "ABI_X86=64 is missing."

echo "${ABI_X86_CURRENT}" | grep -qw "32" || \
    die "ABI_X86=32 is missing."

echo "Multilib: OK"

# ------------------------------------------------------------
# Initial world update
# ------------------------------------------------------------

msg "UPDATING BASE SYSTEM"

emerge \
    --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

msg "CONFIGURING LOCALE"

cat > /etc/locale.gen <<EOF
en_US.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

msg "CONFIGURING TIMEZONE"

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || \
    die "Invalid timezone: ${TIMEZONE}"

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
# Kernel + firmware
# ------------------------------------------------------------

msg "INSTALLING KERNEL AND FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

# ------------------------------------------------------------
# KDE Plasma
# ------------------------------------------------------------

msg "INSTALLING KDE PLASMA"

emerge \
    --ask=n \
    kde-plasma/plasma-meta

# ------------------------------------------------------------
# KDE applications
# ------------------------------------------------------------

msg "INSTALLING KDE APPLICATIONS"

emerge \
    --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ------------------------------------------------------------
# System utilities
# ------------------------------------------------------------

msg "INSTALLING SYSTEM UTILITIES"

emerge \
    --ask=n \
    app-admin/sudo \
    app-editors/nano \
    app-portage/gentoolkit \
    app-portage/eix \
    sys-apps/pciutils \
    sys-apps/usbutils \
    sys-process/htop

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "CONFIGURING NETWORKMANAGER"

emerge \
    --ask=n \
    net-misc/networkmanager

rc-update add NetworkManager default

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

msg "CONFIGURING D-BUS"

emerge \
    --ask=n \
    sys-apps/dbus

rc-update add dbus default

# ------------------------------------------------------------
# elogind
# ------------------------------------------------------------

msg "CONFIGURING ELOGIND"

emerge \
    --ask=n \
    sys-auth/elogind

rc-update add elogind boot

# ------------------------------------------------------------
# SDDM
# ------------------------------------------------------------

msg "CONFIGURING SDDM"

emerge \
    --ask=n \
    x11-misc/sddm \
    gui-libs/display-manager-init

cat > /etc/conf.d/display-manager <<EOF
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# PipeWire
# ------------------------------------------------------------

msg "INSTALLING PIPEWIRE"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURING AMD GPU"

echo
echo "VIDEO_CARDS=${VIDEO_CARDS}"
echo
echo "AMD Radeon userspace stack will use:"
echo "  amdgpu"
echo "  radeonsi"
echo

# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

msg "CONFIGURING 8 GiB ZRAM"

cat > /etc/init.d/zram-swap <<'ZRAM_EOF'
#!/sbin/openrc-run

description="8 GiB compressed zram swap"

depend() {
    need localmount
    after bootmisc
}

start_pre() {
    modprobe zram num_devices=1

    if [ ! -b /dev/zram0 ]; then
        eerror "/dev/zram0 was not created"
        return 1
    fi

    zramctl --reset /dev/zram0 2>/dev/null || true

    zramctl \
        --algorithm zstd \
        --size 8G \
        /dev/zram0

    mkswap \
        -L zram0 \
        /dev/zram0 \
        >/dev/null
}

start() {
    ebegin "Enabling 8 GiB zram swap"

    swapon \
        --priority 100 \
        /dev/zram0

    eend $?
}

stop() {
    ebegin "Disabling zram swap"

    swapoff \
        /dev/zram0 \
        2>/dev/null || true

    zramctl \
        --reset \
        /dev/zram0 \
        2>/dev/null || true

    eend 0
}
ZRAM_EOF

chmod +x /etc/init.d/zram-swap

rc-update add zram-swap default

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

msg "INSTALLING GRUB"

emerge \
    --ask=n \
    sys-boot/grub \
    sys-boot/efibootmgr

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -f /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

# ------------------------------------------------------------
# User
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

if id "${USERNAME}" >/dev/null 2>&1; then

    usermod \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"

else

    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"

fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "root:${ROOT_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

msg "CONFIGURING SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

visudo -c

# ------------------------------------------------------------
# Final world update
# ------------------------------------------------------------

msg "FINAL WORLD UPDATE"

emerge \
    --ask=n \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ------------------------------------------------------------
# Kernel verification
# ------------------------------------------------------------

msg "VERIFYING KERNEL"

KERNEL_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' |
    wc -l
)"

INITRAMFS_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'initramfs-*' |
    wc -l
)"

echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

echo
echo "Initramfs:"
ls -lh /boot/initramfs-* 2>/dev/null || true

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image found."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs found."

# ------------------------------------------------------------
# Regenerate GRUB
# ------------------------------------------------------------

msg "REGENERATING GRUB"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration is empty."

# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC"

rc-update add NetworkManager default
rc-update add dbus default
rc-update add elogind boot
rc-update add display-manager default
rc-update add zram-swap default

echo
rc-update show

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

msg "FINAL VERIFICATION"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo
echo "ABI:"
emerge --info | grep '^ABI_X86='

echo
echo "Architecture:"
emerge --info | grep '^CHOST='

echo
echo "Video:"
emerge --info | grep '^VIDEO_CARDS='

echo
echo "Kernel:"
ls -lh /boot/vmlinuz-* 2>/dev/null

echo
echo "Initramfs:"
ls -lh /boot/initramfs-* 2>/dev/null

echo
echo "EFI:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
    2>/dev/null || true

echo
echo "User:"
id "${USERNAME}"

echo
echo "GRUB:"
ls -lh /boot/grub/grub.cfg

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname     : ${HOSTNAME}"
echo "User         : ${USERNAME}"
echo "Profile      : ${PROFILE}"
echo "Desktop      : KDE Plasma"
echo "Display      : SDDM"
echo "Init         : OpenRC"
echo "Network      : NetworkManager"
echo "Audio        : PipeWire + WirePlumber"
echo "Kernel       : gentoo-kernel-bin"
echo "GPU          : AMD Radeon"
echo "Architecture : amd64 multilib"
echo "ABI_X86      : 64 32"
echo "Swap         : 8 GiB zram"
echo
echo "============================================================"
echo
echo "Installation finished successfully."
echo "You can now reboot."
echo

exit 0
