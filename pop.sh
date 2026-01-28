# Update and cleanup system
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && \
sudo apt remove --purge thunderbird vim -y && \

# Configure Compose Key (Right Alt) for US Layout
mkdir -p ~/.config/cosmic/com.system76.CosmicComp/v1/ && \
echo '( rules: "", model: "", layout: "us", variant: "", options: Some("compose:ralt"), repeat_delay: 600, repeat_rate: 25 )' > ~/.config/cosmic/com.system76.CosmicComp/v1/xkb_config && \

# Audio optimization (Sample Rates)
mkdir -p ~/.config/pipewire/pipewire.conf.d/ && \
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf && \

# Restart PipeWire service
systemctl --user restart pipewire
