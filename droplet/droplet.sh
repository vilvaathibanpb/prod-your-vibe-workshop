#!/usr/bin/env bash
# droplet start | reset | console | status
# Your practice server: its own IP address, SSH on port 22, 1 GB RAM and 1 CPU,
# like a DigitalOcean droplet created with your SSH key.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
NAME=droplet
NET=dropletnet
IP=172.20.0.10
PUBKEY="$HOME/.ssh/id_ed25519.pub"

# Like pasting your public key into DigitalOcean's "Create Droplet" form.
install_key() {
  [ -f "$PUBKEY" ] || ssh-keygen -q -t ed25519 -N '' -C "$(whoami)@codespace" -f "${PUBKEY%.pub}"
  docker exec -i "$NAME" bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < "$PUBKEY"
}

start() {
  docker build -q -t droplet:latest "$DIR" >/dev/null   # cached after the first time
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create --subnet 172.20.0.0/24 "$NET" >/dev/null
  if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    docker start "$NAME" >/dev/null
  else
    # 8080/8443 → the server's web ports, for the codespace Ports tab.
    # 127.0.0.1:2222 is only for the automated test scripts; attendees use the IP.
    docker run -d --name "$NAME" --hostname "$NAME" \
      --network "$NET" --ip "$IP" \
      --memory 1g --memory-swap 1g --cpus 1 \
      --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --tmpfs /run --tmpfs /run/lock \
      -p 8080:80 -p 8443:443 -p 127.0.0.1:2222:22 \
      droplet:latest >/dev/null
    install_key
  fi
  echo "droplet is up · IP $IP · ssh root@$IP (key: $PUBKEY)"
}

status() {
  local state
  state=$(docker exec "$NAME" systemctl is-system-running 2>/dev/null || true)
  echo "${state:-stopped} · IP $IP"
}

case "${1:-start}" in
  start)   start ;;
  reset)   docker rm -f "$NAME" >/dev/null 2>&1 || true
           ssh-keygen -R "$IP" >/dev/null 2>&1 || true   # new server = new identity
           start ;;
  console) docker exec -it "$NAME" bash ;;   # like DO's "Recovery Console"
  status)  status ;;                        # like the droplet page in DO's dashboard
  *) echo "usage: droplet start|reset|console|status"; exit 1 ;;
esac
