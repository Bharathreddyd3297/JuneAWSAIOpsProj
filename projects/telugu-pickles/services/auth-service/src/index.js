// auth-service — customer accounts, login, JWT issuing.
// Owns database: auth_db
const bcrypt = require('bcryptjs');
const { createService, ah, HttpError } = require('../../common/service');
const { initDatabase } = require('../../common/db');
const { signToken, requireAuth } = require('../../common/auth');

const { app, log, start } = createService({ name: 'auth-service' });
const PORT = Number(process.env.PORT || 4001);
let pool;

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS users (
     id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     name          VARCHAR(120) NOT NULL,
     email         VARCHAR(200) NOT NULL UNIQUE,
     phone         VARCHAR(20),
     password_hash VARCHAR(100) NOT NULL,
     created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
   )`,
];

const DEMO_USER = { name: 'Lakshmi Reddy', email: 'demo@telugupickles.in', phone: '9876543210', password: 'Pickle@123' };

async function seed(c) {
  const hash = await bcrypt.hash(DEMO_USER.password, 10);
  await c.query(
    `INSERT INTO users (name, email, phone, password_hash) VALUES ($1,$2,$3,$4)
     ON CONFLICT (email) DO NOTHING`,
    [DEMO_USER.name, DEMO_USER.email, DEMO_USER.phone, hash]
  );
}

const publicUser = (u) => ({ id: u.id, name: u.name, email: u.email, phone: u.phone, createdAt: u.created_at });
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

app.post(
  '/auth/register',
  ah(async (req, res) => {
    const { name, email, phone, password } = req.body || {};
    if (!name || !email || !password) throw new HttpError(400, 'Name, email and password are required');
    if (!EMAIL_RE.test(email)) throw new HttpError(400, 'Please enter a valid email');
    if (String(password).length < 8) throw new HttpError(400, 'Password must be at least 8 characters');

    const hash = await bcrypt.hash(password, 10);
    try {
      const { rows } = await pool.query(
        `INSERT INTO users (name, email, phone, password_hash) VALUES ($1, lower($2), $3, $4) RETURNING *`,
        [name.trim(), email.trim(), phone || null, hash]
      );
      const user = rows[0];
      log.info('user registered', { userId: user.id });
      res.status(201).json({ token: signToken(user), user: publicUser(user) });
    } catch (err) {
      if (err.code === '23505') throw new HttpError(409, 'An account with this email already exists');
      throw err;
    }
  })
);

app.post(
  '/auth/login',
  ah(async (req, res) => {
    const { email, password } = req.body || {};
    if (!email || !password) throw new HttpError(400, 'Email and password are required');
    const { rows } = await pool.query('SELECT * FROM users WHERE email = lower($1)', [email.trim()]);
    const user = rows[0];
    // Same message for unknown email and wrong password (no account enumeration)
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      log.warn('login failed', { requestId: req.id });
      throw new HttpError(401, 'Invalid email or password');
    }
    res.json({ token: signToken(user), user: publicUser(user) });
  })
);

app.get(
  '/auth/me',
  requireAuth,
  ah(async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM users WHERE id = $1', [req.user.id]);
    if (!rows[0]) throw new HttpError(404, 'User not found');
    res.json({ user: publicUser(rows[0]) });
  })
);

app.put(
  '/auth/me',
  requireAuth,
  ah(async (req, res) => {
    const { name, phone } = req.body || {};
    const { rows } = await pool.query(
      `UPDATE users SET name = COALESCE($2, name), phone = COALESCE($3, phone) WHERE id = $1 RETURNING *`,
      [req.user.id, name || null, phone || null]
    );
    res.json({ user: publicUser(rows[0]) });
  })
);

start({
  port: PORT,
  init: async () => {
    pool = await initDatabase({ dbName: process.env.DB_NAME || 'auth_db', migrations: MIGRATIONS, seed, log });
  },
  check: () => pool.query('SELECT 1'),
});
