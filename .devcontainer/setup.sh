#!/usr/bin/env bash
# Make "ssh root@droplet" work from the codespace ("your laptop").
set -e
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -q 'Host droplet' ~/.ssh/config 2>/dev/null || cat >> ~/.ssh/config <<'CFG'
Host droplet
  HostName localhost
  Port 2222
CFG
chmod 600 ~/.ssh/config
sudo ln -sf "$PWD/droplet/droplet.sh" /usr/local/bin/droplet
