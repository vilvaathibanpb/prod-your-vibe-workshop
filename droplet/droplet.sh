#!/usr/bin/env bash
# droplet start | reset | console | status
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
NAME=droplet

start() {
  docker image inspect droplet:latest >/dev/null 2>&1 || docker build -q -t droplet:latest "$DIR"
  if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    docker start "$NAME" >/dev/null
  else
    docker run -d --name "$NAME" --hostname "$NAME" \
      --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      --tmpfs /run --tmpfs /run/lock \
      -p 2222:22 -p 8080:80 -p 8443:443 \
      droplet:latest >/dev/null
  fi
  echo "droplet is up → ssh root@droplet (password: vibes)"
}

case "${1:-start}" in
  start)   start ;;
  reset)   docker rm -f "$NAME" >/dev/null 2>&1 || true; ssh-keygen -R "[localhost]:2222" >/dev/null 2>&1 || true; start ;;
  console) docker exec -it "$NAME" bash ;;   # like DO's "Recovery Console"
  status)  docker exec "$NAME" systemctl is-system-running || true ;;
  *) echo "usage: droplet start|reset|console|status"; exit 1 ;;
esac
