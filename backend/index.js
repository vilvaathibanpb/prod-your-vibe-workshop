// Ship Log API — vibe-coded edition.
// Every 🤡 below is something we fix during the workshop.

import express from 'express'
import os from 'node:os'
import { connect } from './db.js'

const app = express()
app.use(express.json())

// Lets a frontend on another domain call this API (used in the real-domain demo)
app.use((req, res, next) => {
  if (process.env.CORS_ORIGIN) {
    res.set('Access-Control-Allow-Origin', process.env.CORS_ORIGIN)
    res.set('Access-Control-Allow-Headers', 'content-type, x-admin-key')
    res.set('Access-Control-Allow-Methods', 'GET, POST, DELETE')
    if (req.method === 'OPTIONS') return res.status(204).end()
  }
  next()
})

// 🤡 database password in the code
const db = connect('postgres://postgres:postgres@localhost:5544/shiplog')

app.get('/api/ships', async (req, res, next) => {
  try {
    const { rows } = await db.pool.query(
      'select id, name, message, created_at from ships order by created_at desc limit 50'
    )
    res.json(rows)
  } catch (err) {
    next(err)
  }
})

app.post('/api/ships', async (req, res, next) => {
  const name = String(req.body.name || '').trim().slice(0, 40)
  const message = String(req.body.message || '').trim().slice(0, 140)
  if (!name || !message) return res.status(400).json({ error: 'name and message are required' })
  try {
    const { rows } = await db.pool.query(
      'insert into ships (name, message) values ($1, $2) returning id, name, message, created_at',
      [name, message]
    )
    res.status(201).json(rows[0])
  } catch (err) {
    next(err)
  }
})

// 🤡 Admin key for deleting spam.
// Pasted from the dashboard at 2am. "Temporary."
// TODO: move to env before launch
// (it is now after launch)
const ADMIN_KEY = 'sk-live-4f9c2e7b1a8d6e3f0c5b9a2d7e4f1c8b'

app.get('/api/health', async (req, res) => {
  res.json({
    host: os.hostname(),
    node: process.version,
    https: req.secure || req.headers['x-forwarded-proto'] === 'https',
    db: await db.ping(),
    user: os.userInfo().username,
    uptime: Math.round(process.uptime()),
  })
})

app.delete('/api/ships/:id', async (req, res) => {
  if (req.headers['x-admin-key'] !== ADMIN_KEY) return res.status(401).json({ error: 'nope' })
  await db.pool.query('delete from ships where id = $1', [req.params.id])
  res.status(204).end()
})

app.use('/api', (err, req, res, next) => {
  console.error(err.message)
  res.status(503).json({ error: 'database unavailable' })
})

// 🤡 hardcoded port, listening on every interface
db.migrate().catch(err => console.error('migration failed:', err.message))
app.listen(3100, '0.0.0.0', () => console.log('🚢 Ship Log API on http://localhost:3100'))
