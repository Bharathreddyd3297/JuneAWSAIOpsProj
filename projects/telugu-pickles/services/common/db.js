// Database bootstrap shared by every stateful service.
//
// Pattern: "database-per-service" on one PostgreSQL server.
// On startup each service:
//   1. waits for Postgres (retry with backoff)
//   2. creates ITS OWN database if missing   (no init scripts / restore jobs needed)
//   3. runs idempotent migrations            (CREATE TABLE IF NOT EXISTS ...)
//   4. optionally seeds data                 (UPSERTs, safe to re-run)
//
// Connection settings come from the standard libpq env vars:
//   PGHOST, PGPORT, PGUSER, PGPASSWORD  (+ DB_NAME chosen per service)
const { Pool, Client } = require('pg');
const { dependencyErrorsTotal } = require('./metrics');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function withRetry(fn, { attempts = 30, delayMs = 2000, log, what }) {
  let lastErr;
  for (let i = 1; i <= attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      log.warn(`${what} failed, retrying`, { attempt: i, of: attempts, error: err.message });
      await sleep(Math.min(delayMs * i, 10000));
    }
  }
  throw lastErr;
}

async function ensureDatabase(dbName, log) {
  await withRetry(
    async () => {
      const admin = new Client({ database: process.env.PG_ADMIN_DB || 'postgres' });
      await admin.connect();
      try {
        const { rowCount } = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);
        if (rowCount === 0) {
          try {
            // identifiers cannot be parameterised; dbName comes from our own config, not users
            await admin.query(`CREATE DATABASE "${dbName.replace(/"/g, '')}"`);
            log.info('database created', { db: dbName });
          } catch (e) {
            if (e.code !== '42P04') throw e; // 42P04 = already exists (another replica won the race)
          }
        }
      } finally {
        await admin.end();
      }
    },
    { log, what: `connect/create database ${dbName}` }
  );
}

async function initDatabase({ dbName, migrations = [], seed, log }) {
  await ensureDatabase(dbName, log);
  const pool = new Pool({
    database: dbName,
    max: Number(process.env.DB_POOL_MAX || 10),
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });
  pool.on('error', (err) => {
    dependencyErrorsTotal.inc({ dependency: 'postgres' });
    log.error('postgres pool error', { err });
  });

  // Serialise migrations across replicas with an advisory lock.
  const c = await pool.connect();
  try {
    await c.query('SELECT pg_advisory_lock(424242)');
    for (const sql of migrations) await c.query(sql);
    if (seed) await seed(c);
  } finally {
    await c.query('SELECT pg_advisory_unlock(424242)').catch(() => {});
    c.release();
  }
  log.info('database ready', { db: dbName, migrations: migrations.length });
  return pool;
}

module.exports = { initDatabase, withRetry, sleep };
