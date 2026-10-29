import pg from 'pg'

export function connect(url) {
  const pool = new pg.Pool({ connectionString: url })
  // Postgres restarting must not take the whole app down with it
  pool.on('error', err => console.error('db connection lost:', err.message))

  async function migrate() {
    await pool.query(`
      create table if not exists ships (
        id serial primary key,
        name text not null,
        message text not null,
        created_at timestamptz not null default now()
      )
    `)
  }

  async function ping() {
    try {
      await pool.query('select 1')
      return true
    } catch {
      return false
    }
  }

  return { pool, migrate, ping }
}
