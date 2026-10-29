# Prod Your Vibe: Localhost Is Not a Business Model

React India workshop: take a vibe-coded app from localhost to a locked-down, production-ready server.

## Start here

1. **Use this template → Create a new repository** → name it `prod-your-vibe-workshop`, **Private**.
2. On your copy: **Code → Codespaces → ⋯ → New with options** → 2-core, region Southeast Asia → **Create codespace**.
3. In the codespace terminal: `droplet status` should print `running`.
4. Follow [COMMANDS.md](COMMANDS.md): every command, in order (Lab 0 → Lab 3).

## What's inside

| Folder | What |
|---|---|
| `backend/` | Ship Log API: Express + Postgres (the 🤡 comments are what we fix) |
| `frontend/` | Ship Log page: React + Vite, built to static files nginx serves |
| `.github/workflows/deploy.yml` | Auto-deploy on push (switched off until you set it up) |
| `droplet/` | The practice Ubuntu server that runs inside your codespace |
| `.devcontainer/` | Codespace setup |

Helpers inside the codespace: `droplet reset` (fresh server), `droplet console` (get in when locked out).

When you're done, delete your codespace at github.com/codespaces to save your free hours.

## Local dev

```bash
cd backend && npm install && npm run db && npm run dev   # API on :3100, Postgres on :5544
cd frontend && npm install && npm run dev                # page on :5180, /api proxied to :3100
```
