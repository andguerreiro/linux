# Update and cleanup system
sudo apt update && sudo apt upgrade -y && \
sudo apt remove --purge thunderbird vim -y && \
sudo apt autoremove -y

# Audio optimization (Sample Rates)
mkdir -p ~/.config/pipewire/pipewire.conf.d/ && \
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 88200 96000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf && \
systemctl --user restart pipewire
