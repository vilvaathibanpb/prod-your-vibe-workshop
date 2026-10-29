#!/usr/bin/env bash
# Replays every lab command from the guide (non-interactive equivalents) against a fresh droplet.
set -uo pipefail
cd "$(dirname "$0")/.."
KEY=$(mktemp -d)/k; ssh-keygen -q -t ed25519 -N '' -f "$KEY"; chmod 600 "$KEY"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222"
R="$SSH root@localhost"; U="$SSH deploy@localhost"
pass=0; fail=0
check() { local n="$1"; shift; if "$@" >/tmp/vl_out 2>&1; then echo "PASS  $n"; pass=$((pass+1)); else echo "FAIL  $n"; tail -6 /tmp/vl_out | sed 's/^/      /'; fail=$((fail+1)); fi; }

bash droplet/droplet.sh reset >/dev/null
for i in $(seq 30); do docker exec droplet systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded' && break; sleep 1; done
# "Create Droplet with your SSH key": droplet.sh installs ~/.ssh key; add this script's key too
docker exec -i droplet bash -c 'cat >> /root/.ssh/authorized_keys' < "$KEY.pub"

# ---------- Lab 1 ----------
check "L1 ssh root with key"        $R true
check "L1 password login is off"    $R "sshd -T | grep -qx 'passwordauthentication no'"
check "L1 adduser + sudo group"     $R "adduser --disabled-password --gecos '' deploy && echo deploy:pw | chpasswd && usermod -aG sudo deploy"
check "L1 rsync keys to deploy"     $R "rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy"
check "L1 ufw allow + enable"       $R "ufw allow OpenSSH && ufw --force enable && ufw status | grep -q 'Status: active'"
check "L1 deploy + sudo"            $U "echo pw | sudo -S whoami | grep -qx root"
check "L1 PermitRootLogin no"       $R "echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/00-hardening.conf && systemctl restart ssh"
check "L1 root refused"             bash -c "sleep 1; ! $R true"
check "L1 deploy still works"       $U true
# sudo -S is awkward to script; give deploy passwordless sudo for the rest (removed before the deploy test)
$U "echo pw | sudo -S -p '' bash -c 'echo \"deploy ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/zz-test && chmod 440 /etc/sudoers.d/zz-test'" >/dev/null 2>&1

# ---------- Lab 2 ----------
check "L2 install node, caddy, git" $U "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1 && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs caddy git >/dev/null && node -v | grep -q ^v22 && systemctl is-active caddy"
check "L2 install pm2"              $U "sudo npm install -g pm2 >/dev/null 2>&1 && pm2 -v"
# git clone equivalent: a local bare repo on the droplet stands in for GitHub
tar -C . --exclude=node_modules --exclude=dist -czf /tmp/vl_app.tgz backend frontend .github
docker cp /tmp/vl_app.tgz droplet:/tmp/app.tgz
check "L2 git clone"                $U "mkdir -p /tmp/src && tar -C /tmp/src -xzf /tmp/app.tgz && git -C /tmp/src init -q && git -C /tmp/src add -A && git -C /tmp/src -c user.name=t -c user.email=t@t commit -qm start && git clone -q --bare /tmp/src ~/github.git && git clone -q ~/github.git ~/shiplog"
check "L2 backend npm ci"           $U "cd ~/shiplog/backend && npm ci --no-audit --no-fund >/dev/null 2>&1"
check "L2 pm2 start"                $U "cd ~/shiplog/backend && pm2 start index.js --name shiplog >/dev/null && sleep 2 && curl -s localhost:3100/api/health | grep -q '\"db\":false'"
check "L2 pm2 startup + save"       $U "eval \"\$(pm2 startup 2>/dev/null | grep '^sudo env')\" >/dev/null && pm2 save >/dev/null && systemctl is-enabled pm2-deploy"
check "L2 restarts after crash"     $U "kill -9 \$(pm2 pid shiplog); sleep 3; pm2 jlist | grep -q '\"restart_time\":1' && curl -sf localhost:3100/api/health"
check "L2 pm2 logs"                 $U "pm2 logs shiplog --lines 5 --nostream | grep -q 'Ship Log API'"
check "L2 frontend build + publish" $U "cd ~/shiplog/frontend && npm ci --no-audit --no-fund >/dev/null 2>&1 && npm run build >/dev/null && sudo mkdir -p /var/www/shiplog && sudo chown deploy /var/www/shiplog && cp -r dist/. /var/www/shiplog/ && test -f /var/www/shiplog/index.html"
check "L2 Caddyfile + reload"       $U "sudo tee /etc/caddy/Caddyfile >/dev/null <<'CADDY'
:80 {
	handle /api/* {
		reverse_proxy 127.0.0.1:3100
	}
	handle {
		root * /var/www/shiplog
		try_files {path} /index.html
		file_server
	}
}
CADDY
sudo systemctl reload caddy"
check "L2 blocked before ufw rule"  bash -c "! curl -s -m 3 localhost:8080/api/health"
check "L2 ufw 80,443"               $U "sudo ufw allow 80,443/tcp"
check "L2 :8080 → frontend"         bash -c "sleep 1; curl -s -m 5 localhost:8080/ | grep -q '<div id=\"root\">'"
check "L2 :8080/some/page → SPA"    bash -c "curl -s -m 5 localhost:8080/some/page | grep -q '<div id=\"root\">'"
check "L2 :8080/api → backend"      bash -c "curl -s -m 5 localhost:8080/api/health | grep -q '\"user\":\"deploy\"'"
check "L2 post fails (no DB)"       bash -c "curl -s -XPOST localhost:8080/api/ships -H 'content-type: application/json' -d '{\"name\":\"a\",\"message\":\"b\"}' | grep -q 'database unavailable'"

# ---------- Lab 3 ----------
check "L3 postgres + user + db"     $U "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql >/dev/null && sudo -u postgres psql -qc \"create role shiplog login password 's3cret'\" && sudo -u postgres createdb -O shiplog shiplog"
check "L3 edit, push, pull"         $U "git clone -q ~/github.git /tmp/laptop && cd /tmp/laptop/backend && sed -i \"s#connect('postgres://postgres:postgres@localhost:5544/shiplog')#connect(process.env.DATABASE_URL)#; s#^const ADMIN_KEY = .*#const ADMIN_KEY = process.env.ADMIN_KEY#; s#app.listen(3100, '0.0.0.0'#app.listen(process.env.PORT || 3100, '127.0.0.1'#\" index.js && git -c user.name=t -c user.email=t@t commit -qam 'Read config from environment' && git push -q && git -C ~/shiplog pull -q && grep -q 'process.env.DATABASE_URL' ~/shiplog/backend/index.js"
check "L3 secrets file, deploy-only" $U "printf 'DATABASE_URL=postgres://shiplog:s3cret@127.0.0.1:5432/shiplog\nADMIN_KEY=%s\n' \$(openssl rand -hex 32) > ~/shiplog.env && chmod 600 ~/shiplog.env && stat -c %a ~/shiplog.env | grep -qx 600"
check "L3 pm2 restart with env-file" $U "pm2 restart shiplog --node-args=\"--env-file=/home/deploy/shiplog.env\" >/dev/null && pm2 save >/dev/null && sleep 2 && curl -s localhost:3100/api/health | grep -q '\"db\":true'"
check "L3 post a ship via caddy"    bash -c "curl -s -XPOST localhost:8080/api/ships -H 'content-type: application/json' -d '{\"name\":\"tester\",\"message\":\"the labs\"}' | grep -q tester"
check "L3 env survives reboot path" $U "pm2 kill >/dev/null && pm2 resurrect >/dev/null && sleep 2 && curl -s localhost:3100/api/health | grep -q '\"db\":true'"
check "L3 nightly backup (crontab)" $U "echo '0 3 * * * pg_dump shiplog | gzip > ~/shiplog-\$(date +\%a).sql.gz' | sudo crontab -u postgres - && sudo crontab -u postgres -l | grep -q pg_dump && sudo -u postgres bash -c \"cd ~ && \$(sudo crontab -u postgres -l | grep pg_dump | cut -d' ' -f6- | sed 's/\\\\\\\\%/%/g')\" && sudo ls /var/lib/postgresql | grep -q 'shiplog-.*sql.gz'"
check "L3 restore drill"            $U "sudo -u postgres pg_dump shiplog > ~/now.sql 2>/dev/null && sudo -u postgres psql -q shiplog -c 'drop table ships' 2>/dev/null && ! curl -sf localhost:3100/api/ships && sudo -u postgres psql -q shiplog < ~/now.sql >/dev/null 2>&1 && curl -s localhost:3100/api/ships | grep -q tester"
check "L3 only caddy+ssh public"    $U "sudo ss -tlnp | grep -q '127.0.0.1:3100' && sudo ss -tlnp | grep -q '127.0.0.1:5432' && ! sudo ss -tlnp | grep -q '0.0.0.0:3100'"

# ---------- Demo: domains + auto-deploy (what can run here) ----------
check "Demo domains Caddyfile valid" $U "cat > /tmp/Caddyfile.domains <<'CADDY'
shiplog.bus-music.xyz {
	root * /var/www/shiplog
	try_files {path} /index.html
	file_server
}

shiplog-api.bus-music.xyz {
	reverse_proxy 127.0.0.1:3100
}
CADDY
caddy validate --adapter caddyfile --config /tmp/Caddyfile.domains"
$U "sudo rm /etc/sudoers.d/zz-test" >/dev/null 2>&1
# the workflow's steps, exactly as written in .github/workflows/deploy.yml, run as deploy with no sudo
STEPS=$(awk "/<<'STEPS'/{f=1;next}/^ *STEPS$/{f=0}f" .github/workflows/deploy.yml)
check "Demo workflow steps, no sudo" $U "cd /tmp/laptop && sed -i 's#<h1>🚢 Ship Log</h1>#<h1>🚢 Ship Log · deployed</h1>#' frontend/src/App.jsx && git -c user.name=t -c user.email=t@t commit -qam title && git push -q && bash -se <<'X' && grep -rq 'Ship Log · deployed' /var/www/shiplog/assets/
$STEPS
X"
check "Demo site still up after deploy" bash -c "sleep 2; curl -s -m 5 localhost:8080/api/health | grep -q '\"db\":true'"

echo; echo "RESULT: $pass passed, $fail failed"
