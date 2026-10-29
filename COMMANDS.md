# Workshop commands (codespace)

Every command you type today, in order. Your server's IP is `172.20.0.10`.
Each step says where it runs: **codespace** (your codespace terminal), **root** or **deploy** (logged in to the server as that user). Copy the commands exactly as shown.

## 0 · Setup

In the **codespace**, check your server is up (shows its IP):

```bash
droplet status
```

In the **codespace**, log in as root (type `yes` the first time; no password, your key is already on it):

```bash
ssh root@172.20.0.10
```

## 1 · Lock the door

As **root**, create a normal user (pick a password; you'll type it for `sudo`):

```bash
adduser deploy
```

As **root**, let deploy use admin commands:

```bash
usermod -aG sudo deploy
```

As **root**, let deploy log in with your key:

```bash
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
```

As **root**, firewall: keep SSH open, then switch it on (type `y`):

```bash
ufw allow OpenSSH
ufw enable
```

Open a **new codespace terminal** (the **+** button), log in as deploy, then test sudo (prints `root`):

```bash
ssh deploy@172.20.0.10
sudo whoami
```

Back in the **root** terminal, turn off root login and apply it:

```bash
echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/00-hardening.conf
systemctl restart ssh
```

In the **codespace**, prove it (shows `Permission denied`). From now on, always log in as deploy:

```bash
ssh root@172.20.0.10
```

## 2 · Make it run

Everything in this section runs as **deploy** (`ssh deploy@172.20.0.10`).

Add the Node.js 22 source:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
```

Install Node, the Caddy web server and git:

```bash
sudo apt install -y nodejs caddy git
```

Install PM2 (keeps the app running):

```bash
sudo npm install -g pm2
```

Make the server's own key and print it:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Paste it on GitHub: **your repo → Settings → Deploy keys → Add deploy key** (leave write access off).

Download your code:

```bash
git clone git@github.com:<your-username>/prod-your-vibe-workshop.git ~/shiplog
```

Install the backend and start it with PM2:

```bash
cd ~/shiplog/backend && npm ci
pm2 start index.js --name shiplog
```

Start it at every boot (run the `sudo env PATH=…` line that `pm2 startup` prints, then save):

```bash
pm2 startup
pm2 save
```

Build the frontend:

```bash
cd ~/shiplog/frontend && npm ci && npm run build
```

Make the web folder and publish the files:

```bash
sudo mkdir -p /var/www/shiplog && sudo chown deploy /var/www/shiplog
cp -r dist/. /var/www/shiplog/
```

Write the Caddy config (delete what's there, type this, save with Ctrl+O, Enter, exit with Ctrl+X):

```bash
sudo nano /etc/caddy/Caddyfile
```

```
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
```

Apply it, and open the web ports:

```bash
sudo systemctl reload caddy
sudo ufw allow 80,443/tcp
```

Open the **Ports** tab → port **8080** → 🌐. Ship Log loads (Database ❌ until step 3).

To open it on your phone or share it: in the **Ports** tab, right-click port **8080** → **Port Visibility → Public**. Anyone with the link can open it while your codespace runs.

Optional: crash it on purpose and watch PM2 bring it back:

```bash
kill -9 $(pm2 pid shiplog)
pm2 ls
```

## 3 · Database, secrets, backups

Runs as **deploy**, except the code edit and push, which happen in the **codespace**.

Install Postgres, create the database user (invent a password) and the database:

```bash
sudo apt install -y postgresql
sudo -u postgres createuser --pwprompt shiplog
sudo -u postgres createdb -O shiplog shiplog
```

In the **codespace editor**, change 3 lines in `backend/index.js`:

```js
connect(process.env.DATABASE_URL)                          // was connect('postgres://postgres:postgres@...')
const ADMIN_KEY = process.env.ADMIN_KEY                     // was the 'sk-live-...' string
app.listen(process.env.PORT || 3100, '127.0.0.1', ...)    // was app.listen(3100, '0.0.0.0', ...)
```

Push from the **codespace** terminal:

```bash
git commit -am "Read config from environment" && git push
```

Then as **deploy** on the server, pull it:

```bash
git -C ~/shiplog pull
```

Make a new admin key, write the secrets file, lock it:

```bash
openssl rand -hex 32
nano ~/shiplog.env
chmod 600 ~/shiplog.env
```

```
DATABASE_URL=postgres://shiplog:YOUR_PASSWORD@127.0.0.1:5432/shiplog
ADMIN_KEY=YOUR_RANDOM_STRING
```

Restart with the secrets (Database ✅ after a refresh):

```bash
pm2 restart shiplog --node-args="--env-file=/home/deploy/shiplog.env"
pm2 save
```

Nightly backup (pick 1 for nano, add the line, save):

```bash
sudo crontab -u postgres -e
```

```
0 3 * * * pg_dump shiplog | gzip > ~/shiplog-$(date +\%a).sql.gz
```

Restore drill: back up, delete everything, bring it back:

```bash
sudo -u postgres pg_dump shiplog > ~/now.sql
sudo -u postgres psql shiplog -c 'drop table ships'
sudo -u postgres psql shiplog < ~/now.sql
```

Optional: see what's listening (only Caddy and ssh face the world):

```bash
sudo ss -tlnp
```

## Helpers

| Command | What it does |
|---|---|
| `droplet status` | Is the server up, and its IP |
| `droplet console` | Get in as root without SSH (when locked out) |
| `droplet reset` | Throw the server away and start fresh |
| `pm2 logs shiplog` | The app's logs |

When you're done, delete your codespace at github.com/codespaces.
