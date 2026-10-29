#!/usr/bin/env bash
# Adds the "droplet" helper (start/reset/console/status), the stand-in for DigitalOcean's dashboard.
set -e
sudo ln -sf "$PWD/droplet/droplet.sh" /usr/local/bin/droplet
