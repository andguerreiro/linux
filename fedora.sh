#!/bin/bash

# 1. Update and Enable Repos
echo "Updating and enabling RPM Fusion..."
sudo dnf upgrade -y
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Install Drivers and the VA-API Bridge
echo "Installing Nvidia drivers and VA-API bridge..."
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda libva-nvidia-driver nvidia-vaapi-driver

# 3. Swap to Full Multimedia Codecs (Crucial step)
echo "Swapping to full codecs..."
sudo dnf install -y --allowerasing ffmpeg ffmpeg-libs mpv libva-utils

# 4. Fix the "va_openDriver() returns -1" error
# This creates a symlink so libva can find the nvidia driver where it expects it
echo "Configuring driver paths..."
sudo mkdir -p /usr/lib64/dri/
sudo ln -sf /usr/lib64/dri-nonfree/nvidia_drv_video.so /usr/lib64/dri/nvidia_drv_video.so

# 5. Set System Environment Variables
echo "Setting environment variables..."
sudo bash -c 'cat <<EOF > /etc/environment
LIBVA_DRIVER_NAME=nvidia
MOZ_DISABLE_RDD_SANDBOX=1
NVD_BACKEND=direct
EOF'

# 6. Configure mpv for the RTX 4070
echo "Configuring mpv..."
mkdir -p ~/.config/mpv/
cat <<EOF > ~/.config/mpv/mpv.conf
# Use high-quality GPU output
vo=gpu
# Use NVDEC (Nvidia's native hardware decoding)
hwdec=nvdec
# High-quality profile
profile=gpu-hq
# Scale settings for sharp video
scale=ewe-hanning
cscale=ewe-hanning
EOF

# 7. Finalize Pipewire
echo "Configuring Pipewire..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

echo "Setup complete. Please reboot now."
sleep 2
sudo reboot
