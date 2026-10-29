#!/usr/bin/env bash
# Runs every workshop step against the fake droplet and reports PASS/FAIL.
set -uo pipefail
D="docker exec droplet"
KEY=/tmp/pyv_test_key
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 -p 2222"
pass=0; fail=0
check() { local name="$1"; shift; if "$@" >/tmp/pyv_out 2>&1; then echo "PASS  $name"; pass=$((pass+1)); else echo "FAIL  $name"; sed 's/^/      /' /tmp/pyv_out | tail -5; fail=$((fail+1)); fi; }
wait_boot() { for i in $(seq 1 30); do s=$($D systemctl is-system-running 2>/dev/null); [[ $s == running || $s == degraded ]] && return 0; sleep 1; done; return 1; }

bash "$(dirname "$0")/droplet.sh" reset
check "systemd boots"                    wait_boot
$D systemctl --failed --no-legend
rm -f $KEY $KEY.pub; ssh-keygen -q -t ed25519 -N '' -f $KEY; chmod 600 $KEY
check "sshd listening on :22"            $D systemctl is-active ssh
$D bash -c "mkdir -p /root/.ssh && echo '$(cat $KEY.pub)' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
check "ssh root@droplet with key"        $SSH root@localhost true

# 01 users
$SSH root@localhost "adduser --disabled-password --gecos '' deploy && usermod -aG sudo deploy && echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy && rsync --version >/dev/null 2>&1; mkdir -p /home/deploy/.ssh && cp /root/.ssh/authorized_keys /home/deploy/.ssh/ && chown -R deploy:deploy /home/deploy/.ssh" >/dev/null 2>&1
check "ssh deploy@droplet + sudo"        $SSH deploy@localhost sudo -n true
$SSH deploy@localhost "sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/; s/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart ssh" >/dev/null 2>&1
check "root login now refused"          bash -c "! $SSH root@localhost true"

# 02 firewall
$SSH deploy@localhost "sudo ufw allow OpenSSH && sudo ufw allow 'Nginx Full' 2>/dev/null || sudo ufw allow 80,443/tcp; sudo ufw --force enable" >/dev/null 2>&1
check "ufw active"                       bash -c "$D ufw status | grep -q 'Status: active'"
check "ssh still works through ufw"      $SSH deploy@localhost true
$D bash -c "nohup python3 -m http.server 9999 >/dev/null 2>&1 &" 2>/dev/null || true

# 03 install stack
check "apt install nginx postgresql"     $SSH deploy@localhost "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx postgresql >/dev/null"
check "install Node 22 (nodesource)"     $SSH deploy@localhost "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null && sudo apt-get install -y -qq nodejs >/dev/null && node -v"
check "nginx + postgres active"          $SSH deploy@localhost "systemctl is-active nginx postgresql"

# 04 app as systemd service
$SSH deploy@localhost 'mkdir -p ~/app && cat > ~/app/server.js <<JS
const http=require("http");http.createServer((q,r)=>r.end("hello from "+require("os").hostname()+" secret="+(process.env.SECRET?"set":"missing"))).listen(3000,"127.0.0.1")
JS
echo "SECRET=shh" > ~/app/.env && chmod 600 ~/app/.env
sudo tee /etc/systemd/system/app.service >/dev/null <<UNIT
[Unit]
Description=app
After=network.target
[Service]
User=deploy
WorkingDirectory=/home/deploy/app
EnvironmentFile=/home/deploy/app/.env
ExecStart=/usr/bin/node server.js
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now app' >/dev/null 2>&1
check "app.service running + env secret" bash -c "sleep 1; $SSH deploy@localhost curl -s localhost:3000 | grep -q 'secret=set'"
check "app restarts after kill"          bash -c "$SSH deploy@localhost 'sudo systemctl kill -s KILL app; sleep 3; curl -s localhost:3000' | grep -q hello"

# 05 nginx reverse proxy + https (self-signed here; Let's Encrypt on the real droplet)
$SSH deploy@localhost 'sudo openssl req -x509 -nodes -days 7 -newkey rsa:2048 -subj /CN=droplet -keyout /etc/ssl/private/d.key -out /etc/ssl/certs/d.crt 2>/dev/null
sudo tee /etc/nginx/sites-available/app >/dev/null <<NG
server { listen 80 default_server; location / { proxy_pass http://127.0.0.1:3000; } }
server { listen 443 ssl default_server; ssl_certificate /etc/ssl/certs/d.crt; ssl_certificate_key /etc/ssl/private/d.key; location / { proxy_pass http://127.0.0.1:3000; } }
NG
sudo rm -f /etc/nginx/sites-enabled/default && sudo ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/ && sudo nginx -t && sudo systemctl reload nginx' >/dev/null 2>&1
check "host → :8080 → nginx → app"       bash -c "sleep 2; curl -s localhost:8080 | grep -q hello"
check "host → :8443 https → app"         bash -c "curl -sk https://localhost:8443 | grep -q hello"

# 06 postgres
check "postgres db + user + query"       $SSH deploy@localhost "sudo -u postgres psql -qc \"create user ship with password 'x'\" && sudo -u postgres createdb -O ship shiplog && PGPASSWORD=x psql -h 127.0.0.1 -U ship shiplog -tAc 'select 42' | grep -q 42"
check "pg_dump backup"                   $SSH deploy@localhost "set -o pipefail; PGPASSWORD=x pg_dump -h 127.0.0.1 -U ship shiplog | gzip > ~/backup.sql.gz && test -s ~/backup.sql.gz"

# reboot survival
docker restart droplet >/dev/null
check "reboot: systemd back"             wait_boot
check "reboot: app+nginx+pg+ufw survive" bash -c "sleep 3; curl -s localhost:8080 | grep -q hello && $D systemctl is-active nginx postgresql app && $D ufw status | grep -q active"

# lockout + recovery console
$D bash -c "ufw delete allow OpenSSH >/dev/null; ufw delete allow 22/tcp >/dev/null 2>&1; true"
check "lockout: forgetting ssh rule blocks ssh" bash -c "! $SSH deploy@localhost true"
$D ufw allow OpenSSH >/dev/null
check "recovery console fixes it"        $SSH deploy@localhost true

echo; echo "memory: $($D bash -c "free -m | awk '/Mem/{print \$3\" MB used\"}'")  disk: $($D df -h / | awk 'NR==2{print $3" used"}')"
echo "RESULT: $pass passed, $fail failed"
