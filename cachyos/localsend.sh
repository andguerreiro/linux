
#!/bin/bash

sudo pacman -S localsend

sudo ufw allow from 192.168.15.0/24 to any port 53317 proto tcp
sudo ufw allow from 192.168.15.0/24 to any port 53317 proto udp
