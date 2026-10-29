#!/usr/bin/env bash
# Replays the guide's Lab 1–3 commands (non-interactive equivalents) against a fresh droplet.
set -uo pipefail
cd "$(dirname "$0")/.."
KEY=$(mktemp -d)/k; ssh-keygen -q -t ed25519 -N '' -f "$KEY"; chmod 600 "$KEY"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222"
R="$SSH root@localhost"; U="$SSH deploy@localhost"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/tmp/vl_out 2>&1; then echo "PASS  $n"; pass=$((pass+1)); else echo "FAIL  $n"; tail -6 /tmp/vl_out | sed 's/^/      /'; fail=$((fail+1)); fi; }

bash droplet/droplet.sh reset >/dev/null
for i in $(seq 30); do docker exec droplet systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded' && break; sleep 1; done
# Lab 1.2 ssh-copy-id equivalent
docker exec droplet bash -c "mkdir -p /root/.ssh && echo '$(cat $KEY.pub)' >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
check "L1.2 ssh root with key"  $R true
check "L1.3 create deploy user" $R "adduser --disabled-password --gecos '' deploy && echo deploy:pw | chpasswd && usermod -aG sudo deploy && mkdir -p /home/deploy/.ssh && cp ~/.ssh/authorized_keys /home/deploy/.ssh/ && chown -R deploy:deploy /home/deploy/.ssh && chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys"
check "L1.4 deploy + sudo"      $U "echo pw | sudo -S whoami | grep -qx root"
# from here, sudo with password via -S; wrap as a function on the remote
S='echo pw | sudo -S -p ""'
check "L1.5 hardening drop-in"  $U "$S bash -c \"printf 'PermitRootLogin no\\\\nPasswordAuthentication no\\\\n' > /etc/ssh/sshd_config.d/00-hardening.conf\" && $S sshd -t && $S systemctl restart ssh && $S sshd -T | grep -qx 'permitrootlogin no'"
check "L1.6 root refused"       bash -c "! $R true"
check "L1.6 deploy still works" $U true
check "L1.7 ufw"                $U "$S ufw default deny incoming && $S ufw default allow outgoing && $S ufw allow OpenSSH && $S ufw --force enable && $S ufw status verbose | grep -q 'Status: active'"
# give deploy passwordless sudo for the rest of the script (interactive sudo isn't scriptable cleanly)
$U "$S bash -c 'echo \"deploy ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/zz-test'" >/dev/null 2>&1

# Lab 2
check "L2.1 node+nginx+git"     $U "sudo apt-get update -qq && curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1 && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs nginx git >/dev/null && node -v | grep -q ^v22"
# git clone equivalent: copy the app source (no node_modules/dist)
tar -C . --exclude=node_modules --exclude=dist -czf /tmp/vl_app.tgz backend frontend
docker cp /tmp/vl_app.tgz droplet:/tmp/app.tgz
docker exec droplet bash -c "mkdir -p /home/deploy/shiplog && tar -C /home/deploy/shiplog -xzf /tmp/app.tgz && chown -R deploy:deploy /home/deploy/shiplog"
check "L2.3 backend npm ci"     $U "cd ~/shiplog/backend && npm ci --no-audit --no-fund >/dev/null 2>&1 && test -d node_modules/express"
check "L2.3 frontend build"      $U "cd ~/shiplog/frontend && npm ci --no-audit --no-fund >/dev/null 2>&1 && npm run build >/dev/null && sudo mkdir -p /var/www/shiplog && sudo chown deploy:deploy /var/www/shiplog && cp -r dist/. /var/www/shiplog/ && test -f /var/www/shiplog/index.html"
$U "sudo tee /etc/systemd/system/shiplog.service >/dev/null" <<'UNIT'
[Unit]
Description=Ship Log
After=network.target

[Service]
User=deploy
WorkingDirectory=/home/deploy/shiplog/backend
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=2
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
UNIT
check "L2.4 unit running, no DB" $U "sudo systemctl daemon-reload && sudo systemctl enable --now shiplog && sleep 2 && curl -s localhost:3100/api/health | grep -q '\"db\":false'"
check "L2.5 restarts after kill" $U "sudo systemctl kill -s KILL shiplog; sleep 4; systemctl is-active shiplog && curl -sf localhost:3100/api/health"
$U "sudo tee /etc/nginx/sites-available/shiplog >/dev/null" <<'NG'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/shiplog;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3100;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NG
check "L2.6 nginx site"          $U "sudo ln -s /etc/nginx/sites-available/shiplog /etc/nginx/sites-enabled/ && sudo rm /etc/nginx/sites-enabled/default && sudo nginx -t && sudo systemctl reload nginx"
check "L2.7 blocked before ufw rule" bash -c "! curl -s -m 3 localhost:8080/api/health"
check "L2.7 ufw Nginx Full"      $U "sudo ufw allow 'Nginx Full'"
check "L2.8 :8080 → app"         bash -c "sleep 1; curl -s -m 5 localhost:8080/api/health | grep -q '\"user\":\"deploy\"'"
check "L2.8 :8080 → frontend"    bash -c "curl -s -m 5 localhost:8080/ | grep -q '<div id=\"root\">'"
check "L2.8 post fails (no DB)"  bash -c "curl -s -XPOST localhost:8080/api/ships -H 'content-type: application/json' -d '{\"name\":\"a\",\"message\":\"b\"}' | grep -q 'database unavailable'"

# Lab 3
check "L3.1 postgres + role + db" $U "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql >/dev/null && sudo -u postgres psql -qc \"create role shiplog login password 's3cret'\" && sudo -u postgres createdb --owner shiplog shiplog && psql 'postgres://shiplog:s3cret@127.0.0.1:5432/shiplog' -tAc 'select 1' | grep -qx 1"
# L3.2 code edits exactly as the guide describes
$U "cd ~/shiplog/backend && sed -i \"s#connect('postgres://postgres:postgres@localhost:5544/shiplog')#connect(process.env.DATABASE_URL)#; s#^const ADMIN_KEY = .*#const ADMIN_KEY = process.env.ADMIN_KEY#; s#app.listen(3100, '0.0.0.0'#app.listen(process.env.PORT || 3100, '127.0.0.1'#\" index.js"
check "L3.2 code edits applied"  $U "cd ~/shiplog/backend && grep -q 'connect(process.env.DATABASE_URL)' index.js && grep -q 'ADMIN_KEY = process.env.ADMIN_KEY' index.js && grep -q \"process.env.PORT || 3100, '127.0.0.1'\" index.js"
check "L3.3 env file 600"        $U "printf 'DATABASE_URL=postgres://shiplog:s3cret@127.0.0.1:5432/shiplog\nADMIN_KEY=%s\nPORT=3100\n' \$(openssl rand -hex 32) | sudo tee /etc/shiplog.env >/dev/null && sudo chmod 600 /etc/shiplog.env && ! cat /etc/shiplog.env"
check "L3.4 EnvironmentFile → db ✅" $U "sudo sed -i '/^\[Service\]/a EnvironmentFile=/etc/shiplog.env' /etc/systemd/system/shiplog.service && sudo systemctl daemon-reload && sudo systemctl restart shiplog && sleep 2 && curl -s localhost:3100/api/health | grep -q '\"db\":true'"
check "L3.4 post a ship via nginx" bash -c "curl -s -XPOST localhost:8080/api/ships -H 'content-type: application/json' -d '{\"name\":\"tester\",\"message\":\"the labs\"}' | grep -q tester"
check "L3.5 pgpass + pg_dump"    $U "mkdir -p ~/backups && echo '127.0.0.1:5432:shiplog:shiplog:s3cret' > ~/.pgpass && chmod 600 ~/.pgpass && pg_dump -h 127.0.0.1 -U shiplog shiplog | gzip > ~/backups/now.sql.gz && test \$(stat -c%s ~/backups/now.sql.gz) -gt 200"
check "L3.5 crontab line installs" $U "echo '0 3 * * * pg_dump -h 127.0.0.1 -U shiplog shiplog | gzip > /home/deploy/backups/shiplog-\$(date +\%a).sql.gz' | crontab - && crontab -l | grep -q pg_dump && systemctl is-active cron"
check "L3.5 cron command works"  $U "bash -c \"\$(crontab -l | grep pg_dump | cut -d' ' -f6- | sed 's/\\\\\\\\%/%/g')\" && ls ~/backups/shiplog-*.sql.gz"
check "L3.6 drop + restore"      $U "psql -h 127.0.0.1 -U shiplog shiplog -qc 'drop table ships' && gunzip -c ~/backups/now.sql.gz | psql -q -h 127.0.0.1 -U shiplog shiplog >/dev/null && psql -h 127.0.0.1 -U shiplog shiplog -tAc 'select count(*) from ships' | grep -qx 1"
check "L3.7 only nginx is public" $U "sudo ss -tlnp | grep -q '127.0.0.1:3100' && sudo ss -tlnp | grep -q '127.0.0.1:5432' && ! sudo ss -tlnp | grep -q '0.0.0.0:3100'"
# Live demo bits that can run here
cat > /tmp/vl_deploy.sh <<'DS'
#!/usr/bin/env bash
set -euo pipefail
cd ~/shiplog
git pull --ff-only
cd backend
npm ci --omit=dev
cd ../frontend
npm ci
npm run build
cp -r dist/. /var/www/shiplog/
sudo systemctl restart shiplog
DS
check "Demo sudoers rule valid"  $U "echo 'deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart shiplog' | sudo tee /etc/sudoers.d/shiplog-deploy >/dev/null && sudo chmod 440 /etc/sudoers.d/shiplog-deploy /etc/sudoers.d/zz-test && sudo visudo -c"
check "Demo deploy.sh syntax"    bash -n /tmp/vl_deploy.sh

echo; echo "RESULT: $pass passed, $fail failed"
