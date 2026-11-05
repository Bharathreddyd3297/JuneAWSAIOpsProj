// payment-service — MOCK payment processor (UPI / Card / Cash on Delivery).
// Owns database: payments_db. Internal only: called by order-service, never by browsers.
//
// AIOps demo knobs:
//   PAYMENT_DECLINE_RATE=0.4  -> 40% of UPI/Card payments are declined by the "bank"
//   PAYMENT_LATENCY_MS=3000   -> slow payment gateway
const crypto = require('crypto');
const { createService, ah, HttpError } = require('../../common/service');
const { initDatabase, sleep } = require('../../common/db');
const { paymentsTotal } = require('../../common/metrics');

const { app, log, start } = createService({ name: 'payment-service' });
const PORT = Number(process.env.PORT || 4005);
const DECLINE_RATE = Number(process.env.PAYMENT_DECLINE_RATE || 0);
const LATENCY_MS = Number(process.env.PAYMENT_LATENCY_MS || 0);
const METHODS = ['UPI', 'CARD', 'COD'];
let pool;

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS payments (
     id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     order_id    UUID         NOT NULL,
     user_id     UUID         NOT NULL,
     amount      INTEGER      NOT NULL CHECK (amount > 0),
     method      VARCHAR(10)  NOT NULL,
     status      VARCHAR(20)  NOT NULL,
     reference   VARCHAR(40)  NOT NULL,
     created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
   )`,
  `CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id)`,
];

app.post(
  '/internal/payments',
  ah(async (req, res) => {
    const { orderId, userId, amount, method } = req.body || {};
    if (!orderId || !userId || !(amount > 0)) throw new HttpError(400, 'orderId, userId and amount are required');
    if (!METHODS.includes(method)) throw new HttpError(400, `method must be one of ${METHODS.join(', ')}`);

    if (LATENCY_MS) await sleep(LATENCY_MS);

    let status;
    if (method === 'COD') status = 'COD_PENDING';
    else status = Math.random() < DECLINE_RATE ? 'DECLINED' : 'CAPTURED';

    const reference = `TP${method}${crypto.randomBytes(5).toString('hex').toUpperCase()}`;
    await pool.query(
      `INSERT INTO payments (order_id, user_id, amount, method, status, reference) VALUES ($1,$2,$3,$4,$5,$6)`,
      [orderId, userId, amount, method, status, reference]
    );
    paymentsTotal.inc({ method, result: status });

    if (status === 'DECLINED') {
      log.error('payment declined by bank', { requestId: req.id, orderId, amount, method, reference });
    } else {
      log.info('payment processed', { requestId: req.id, orderId, amount, method, status, reference });
    }
    res.status(status === 'DECLINED' ? 402 : 201).json({ status, reference });
  })
);

app.get(
  '/internal/payments/:orderId',
  ah(async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM payments WHERE order_id = $1 ORDER BY created_at', [req.params.orderId]);
    res.json({ payments: rows });
  })
);

start({
  port: PORT,
  init: async () => {
    pool = await initDatabase({ dbName: process.env.DB_NAME || 'payments_db', migrations: MIGRATIONS, log });
    if (DECLINE_RATE || LATENCY_MS) log.warn('payment fault injection active', { DECLINE_RATE, LATENCY_MS });
  },
  check: () => pool.query('SELECT 1'),
});
