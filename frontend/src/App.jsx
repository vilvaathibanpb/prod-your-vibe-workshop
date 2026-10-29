import { useEffect, useState } from 'react'

// Empty = same domain as the page (nginx sends /api to the backend).
// Set VITE_API_URL at build time when the API lives on its own domain.
const API = import.meta.env.VITE_API_URL || ''

function timeAgo(iso) {
  const s = Math.round((Date.now() - new Date(iso)) / 1000)
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.round(s / 60)}m ago`
  return `${Math.round(s / 3600)}h ago`
}

function VibeCheck() {
  const [health, setHealth] = useState(null)

  useEffect(() => {
    const load = () => fetch(API + '/api/health').then(r => r.json()).then(setHealth).catch(() => setHealth(false))
    load()
    const t = setInterval(load, 5000)
    return () => clearInterval(t)
  }, [])

  if (health === null) return <div className="vibe">checking vibes…</div>
  if (health === false) return <div className="vibe bad">API unreachable 💀</div>

  const checks = [
    { label: 'HTTPS', ok: health.https || location.protocol === 'https:' },
    { label: 'Database', ok: health.db },
    { label: 'Not root', ok: health.user !== 'root' },
  ]

  return (
    <div className="vibe">
      <div className="vibe-title">Prod vibe check</div>
      {checks.map(c => (
        <span key={c.label} className={`chip ${c.ok ? 'ok' : 'bad'}`}>
          {c.ok ? '🔒' : '🔓'} {c.label}
        </span>
      ))}
      <div className="meta">
        🖥️ {health.host} · 👤 {health.user} · node {health.node} · up {health.uptime}s
      </div>
    </div>
  )
}

export default function App() {
  const [ships, setShips] = useState([])
  const [name, setName] = useState(() => localStorage.getItem('shiplog:name') || '')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  const load = () => fetch(API + '/api/ships').then(r => r.json()).then(d => setShips(Array.isArray(d) ? d : [])).catch(() => {})

  useEffect(() => {
    load()
    const t = setInterval(load, 4000)
    return () => clearInterval(t)
  }, [])

  async function submit(e) {
    e.preventDefault()
    setError('')
    localStorage.setItem('shiplog:name', name)
    const res = await fetch(API + '/api/ships', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name, message }),
    })
    if (!res.ok) return setError((await res.json()).error)
    setMessage('')
    load()
  }

  return (
    <main>
      <header>
        <h1>🚢 Ship Log</h1>
        <p>Tell the room what you shipped today.</p>
      </header>

      <VibeCheck />

      <form onSubmit={submit}>
        <input placeholder="your name" value={name} onChange={e => setName(e.target.value)} maxLength={40} />
        <input
          placeholder="I shipped…"
          value={message}
          onChange={e => setMessage(e.target.value)}
          maxLength={140}
        />
        <button>Ship it</button>
      </form>
      {error && <p className="error">{error}</p>}

      <ul>
        {ships.map(s => (
          <li key={s.id}>
            <strong>{s.name}</strong> shipped <span>{s.message}</span>
            <time>{timeAgo(s.created_at)}</time>
          </li>
        ))}
        {ships.length === 0 && <li className="empty">Nothing shipped yet. Be first.</li>}
      </ul>
    </main>
  )
}
