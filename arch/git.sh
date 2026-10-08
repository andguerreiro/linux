#!/usr/bin/env bash
set -euo pipefail

GIT_USER="andguerreiro"
GIT_EMAIL="andguerreiro@yahoo.com"
KEY_PATH="$HOME/.ssh/id_ed25519"

# 1. Install git (and openssh, in case it's missing)
echo ">>> Installing git..."
sudo pacman -S --needed --noconfirm git openssh

# 2. Configure git identity
echo ">>> Configuring git..."
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

# 3. Create the SSH key (skips if one already exists)
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY_PATH" ]; then
    echo ">>> SSH key already exists at $KEY_PATH, reusing it."
else
    echo ">>> Generating SSH key..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_PATH" -N ""
fi

# 4. Start ssh-agent and add the key
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$KEY_PATH"

# 5. Configure SSH to use this key for GitHub
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
fi
chmod 600 "$SSH_CONFIG"

# 6. Show the public key
echo
echo "=============================================================="
echo " Your public SSH key (copy everything below to GitHub):"
echo "=============================================================="
cat "$KEY_PATH.pub"
echo "=============================================================="
echo
echo "Add it at: https://github.com/settings/keys  ->  New SSH key"
echo "Then test with: ssh -T git@github.com"
