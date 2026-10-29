#!/usr/bin/env bash
# ~/deploy.sh on the server: pull, rebuild, restart. Run by hand or by GitHub Actions.
# API on its own domain? Put VITE_API_URL=https://api.example.com in ~/shiplog/frontend/.env.production.local once.
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
echo "deployed $(git rev-parse --short HEAD)"
