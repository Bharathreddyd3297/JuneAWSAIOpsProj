// cart-service — per-user shopping cart.
// Owns database: cart_db. Calls catalog-service for live prices (never trusts client prices).
const { createService, ah, HttpError } = require('../../common/service');
const { initDatabase } = require('../../common/db');
const { requireAuth } = require('../../common/auth');
const { callService } = require('../../common/http');
const { WEIGHTS, unitPrice, totals, FREE_SHIPPING_THRESHOLD } = require('../../common/pricing');

const { app, log, start } = createService({ name: 'cart-service' });
const PORT = Number(process.env.PORT || 4003);
const CATALOG_URL = process.env.CATALOG_SERVICE_URL || 'http://localhost:4002';
const MAX_QTY = 10;
let pool;

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS cart_items (
     user_id    UUID        NOT NULL,
     slug       VARCHAR(80) NOT NULL,
     weight     VARCHAR(10) NOT NULL,
     qty        SMALLINT    NOT NULL CHECK (qty BETWEEN 1 AND ${MAX_QTY}),
     added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
     PRIMARY KEY (user_id, slug, weight)
   )`,
];

function validateLine({ slug, weight, qty }) {
  if (!slug || typeof slug !== 'string') throw new HttpError(400, 'slug is required');
  if (!WEIGHTS[weight]) throw new HttpError(400, `Pack size must be one of ${Object.keys(WEIGHTS).join(', ')}`);
  const n = Number(qty);
  if (!Number.isInteger(n) || n < 0 || n > MAX_QTY) throw new HttpError(400, `Quantity must be 0-${MAX_QTY}`);
  return { slug, weight, qty: n };
}

async function buildCart(req) {
  const { rows } = await pool.query(
    'SELECT slug, weight, qty FROM cart_items WHERE user_id = $1 ORDER BY added_at',
    [req.user.id]
  );
  if (rows.length === 0) {
    return { items: [], subtotal: 0, shipping: 0, total: 0, freeShippingThreshold: FREE_SHIPPING_THRESHOLD };
  }
  const slugs = [...new Set(rows.map((r) => r.slug))].join(',');
  const { products } = await callService('catalog-service', `${CATALOG_URL}/products?slugs=${encodeURIComponent(slugs)}`, { req });
  const bySlug = Object.fromEntries(products.map((p) => [p.slug, p]));

  const items = rows
    .filter((r) => bySlug[r.slug]) // product removed from catalogue -> drop silently
    .map((r) => {
      const p = bySlug[r.slug];
      const price = unitPrice(p.price500g, r.weight);
      return {
        slug: r.slug,
        name: p.name,
        localName: p.localName,
        category: p.category,
        color: p.color,
        weight: r.weight,
        qty: r.qty,
        unitPrice: price,
        lineTotal: price * r.qty,
        inStock: p.inStock,
      };
    });
  return { items, ...totals(items), freeShippingThreshold: FREE_SHIPPING_THRESHOLD };
}

async function assertProductExists(req, slug) {
  await callService('catalog-service', `${CATALOG_URL}/products/${encodeURIComponent(slug)}`, { req });
}

app.use('/cart', requireAuth);

app.get('/cart', ah(async (req, res) => res.json(await buildCart(req))));

// add (increments quantity)
app.post(
  '/cart/items',
  ah(async (req, res) => {
    const line = validateLine({ ...req.body, qty: req.body?.qty ?? 1 });
    if (line.qty === 0) throw new HttpError(400, 'Quantity must be at least 1');
    await assertProductExists(req, line.slug);
    await pool.query(
      `INSERT INTO cart_items (user_id, slug, weight, qty) VALUES ($1,$2,$3,$4)
       ON CONFLICT (user_id, slug, weight) DO UPDATE SET qty = LEAST(cart_items.qty + EXCLUDED.qty, ${MAX_QTY})`,
      [req.user.id, line.slug, line.weight, line.qty]
    );
    res.status(201).json(await buildCart(req));
  })
);

// set exact quantity (0 removes)
app.put(
  '/cart/items',
  ah(async (req, res) => {
    const line = validateLine(req.body || {});
    if (line.qty === 0) {
      await pool.query('DELETE FROM cart_items WHERE user_id=$1 AND slug=$2 AND weight=$3', [req.user.id, line.slug, line.weight]);
    } else {
      await pool.query(
        `INSERT INTO cart_items (user_id, slug, weight, qty) VALUES ($1,$2,$3,$4)
         ON CONFLICT (user_id, slug, weight) DO UPDATE SET qty = EXCLUDED.qty`,
        [req.user.id, line.slug, line.weight, line.qty]
      );
    }
    res.json(await buildCart(req));
  })
);

// merge a guest (browser) cart after login
app.post(
  '/cart/merge',
  ah(async (req, res) => {
    const items = Array.isArray(req.body?.items) ? req.body.items.slice(0, 50) : [];
    for (const raw of items) {
      try {
        const line = validateLine(raw);
        if (line.qty === 0) continue;
        await pool.query(
          `INSERT INTO cart_items (user_id, slug, weight, qty) VALUES ($1,$2,$3,$4)
           ON CONFLICT (user_id, slug, weight) DO UPDATE SET qty = LEAST(cart_items.qty + EXCLUDED.qty, ${MAX_QTY})`,
          [req.user.id, line.slug, line.weight, line.qty]
        );
      } catch (err) {
        log.warn('skipping invalid guest cart line', { requestId: req.id, error: err.message });
      }
    }
    res.json(await buildCart(req));
  })
);

app.delete(
  '/cart',
  ah(async (req, res) => {
    await pool.query('DELETE FROM cart_items WHERE user_id = $1', [req.user.id]);
    res.json({ items: [], subtotal: 0, shipping: 0, total: 0, freeShippingThreshold: FREE_SHIPPING_THRESHOLD });
  })
);

start({
  port: PORT,
  init: async () => {
    pool = await initDatabase({ dbName: process.env.DB_NAME || 'cart_db', migrations: MIGRATIONS, log });
  },
  check: () => pool.query('SELECT 1'),
});
