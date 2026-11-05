// catalog-service — pickle catalogue, search/filter, stock.
// Owns database: catalog_db
const { createService, ah, HttpError } = require('../../common/service');
const { initDatabase } = require('../../common/db');
const { WEIGHTS } = require('../../common/pricing');
const PRODUCTS = require('./products');

const { app, log, start } = createService({ name: 'catalog-service' });
const PORT = Number(process.env.PORT || 4002);
let pool;

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS products (
     slug           VARCHAR(80) PRIMARY KEY,
     name           VARCHAR(120) NOT NULL,
     local_name     VARCHAR(120),
     category       VARCHAR(10)  NOT NULL CHECK (category IN ('veg','non-veg')),
     region         VARCHAR(60)  NOT NULL,
     spice          SMALLINT     NOT NULL CHECK (spice BETWEEN 1 AND 5),
     price_500g     INTEGER      NOT NULL CHECK (price_500g > 0),
     description    TEXT         NOT NULL,
     ingredients    TEXT         NOT NULL,
     shelf_life_days INTEGER     NOT NULL,
     rating         NUMERIC(2,1) NOT NULL,
     reviews        INTEGER      NOT NULL,
     bestseller     BOOLEAN      NOT NULL DEFAULT false,
     color          VARCHAR(7)   NOT NULL,
     stock_grams    INTEGER      NOT NULL DEFAULT 0 CHECK (stock_grams >= 0),
     updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
   )`,
  `CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)`,
];

// UPSERT the catalogue; keeps existing stock so restarts don't reset inventory.
async function seed(c) {
  for (const p of PRODUCTS) {
    await c.query(
      `INSERT INTO products (slug,name,local_name,category,region,spice,price_500g,description,ingredients,
                             shelf_life_days,rating,reviews,bestseller,color,stock_grams)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       ON CONFLICT (slug) DO UPDATE SET
         name=EXCLUDED.name, local_name=EXCLUDED.local_name, category=EXCLUDED.category, region=EXCLUDED.region,
         spice=EXCLUDED.spice, price_500g=EXCLUDED.price_500g, description=EXCLUDED.description,
         ingredients=EXCLUDED.ingredients, shelf_life_days=EXCLUDED.shelf_life_days, rating=EXCLUDED.rating,
         reviews=EXCLUDED.reviews, bestseller=EXCLUDED.bestseller, color=EXCLUDED.color, updated_at=now()`,
      [p.slug, p.name, p.localName, p.category, p.region, p.spice, p.price500g, p.description, p.ingredients,
        p.shelfLifeDays, p.rating, p.reviews, p.bestseller, p.color, p.stockGrams]
    );
  }
  log.info('catalogue seeded', { products: PRODUCTS.length });
}

const toApi = (r) => ({
  slug: r.slug,
  name: r.name,
  localName: r.local_name,
  category: r.category,
  region: r.region,
  spice: r.spice,
  price500g: r.price_500g,
  description: r.description,
  ingredients: r.ingredients,
  shelfLifeDays: r.shelf_life_days,
  rating: Number(r.rating),
  reviews: r.reviews,
  bestseller: r.bestseller,
  color: r.color,
  inStock: r.stock_grams >= 250,
});

const SORTS = {
  popular: 'bestseller DESC, reviews DESC',
  rating: 'rating DESC, reviews DESC',
  'price-asc': 'price_500g ASC',
  'price-desc': 'price_500g DESC',
  spice: 'spice DESC, name ASC',
  name: 'name ASC',
};

// GET /products?category=veg|non-veg&q=&maxSpice=&region=&bestseller=true&sort=&slugs=a,b
app.get(
  '/products',
  ah(async (req, res) => {
    const { category, q, maxSpice, region, bestseller, sort = 'popular', slugs } = req.query;
    const where = [];
    const params = [];
    const add = (sql, v) => {
      params.push(v);
      where.push(sql.replace('?', `$${params.length}`));
    };
    if (category) add('category = ?', category);
    if (region) add('region = ?', region);
    if (maxSpice) add('spice <= ?', Number(maxSpice));
    if (bestseller === 'true') where.push('bestseller = true');
    if (q) {
      params.push(`%${q}%`);
      const n = `$${params.length}`;
      where.push(`(name ILIKE ${n} OR local_name ILIKE ${n} OR region ILIKE ${n} OR ingredients ILIKE ${n})`);
    }
    if (slugs) add('slug = ANY(?)', String(slugs).split(',').slice(0, 100));

    const sql = `SELECT * FROM products ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
                 ORDER BY ${SORTS[sort] || SORTS.popular}`;
    const { rows } = await pool.query(sql, params);
    res.json({ count: rows.length, products: rows.map(toApi) });
  })
);

// NOTE: static routes are registered BEFORE /products/:slug so "/products/categories" is never treated as a slug
app.get(
  '/categories',
  ah(async (_req, res) => {
    const { rows } = await pool.query(`SELECT category, count(*)::int AS count FROM products GROUP BY category`);
    const label = { veg: 'Veg Pickles', 'non-veg': 'Non-Veg Pickles' };
    res.json({ categories: rows.map((r) => ({ id: r.category, name: label[r.category], count: r.count })) });
  })
);

app.get(
  '/regions',
  ah(async (_req, res) => {
    const { rows } = await pool.query(`SELECT region, count(*)::int AS count FROM products GROUP BY region ORDER BY region`);
    res.json({ regions: rows });
  })
);

app.get(
  '/products/:slug',
  ah(async (req, res) => {
    const { rows } = await pool.query('SELECT * FROM products WHERE slug = $1', [req.params.slug]);
    if (!rows[0]) throw new HttpError(404, 'Pickle not found');
    res.json({ product: toApi(rows[0]), packSizes: Object.keys(WEIGHTS) });
  })
);

// ---- Internal API (NOT routed by the gateway; only reachable inside the cluster) ----
const GRAMS = { '250g': 250, '500g': 500, '1kg': 1000 };

async function adjustStock(items, direction) {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    for (const it of items) {
      const grams = (GRAMS[it.weight] || 0) * Number(it.qty || 0);
      if (!grams) throw new HttpError(400, `Invalid item ${it.slug}`);
      const { rows } = await c.query('SELECT stock_grams, name FROM products WHERE slug = $1 FOR UPDATE', [it.slug]);
      if (!rows[0]) throw new HttpError(404, `Pickle ${it.slug} not found`);
      if (direction < 0 && rows[0].stock_grams < grams) {
        throw new HttpError(409, `Sorry, ${rows[0].name} is out of stock for that quantity`);
      }
      await c.query('UPDATE products SET stock_grams = stock_grams + $2, updated_at = now() WHERE slug = $1', [
        it.slug,
        direction * grams,
      ]);
    }
    await c.query('COMMIT');
  } catch (err) {
    await c.query('ROLLBACK');
    throw err;
  } finally {
    c.release();
  }
}

app.post(
  '/internal/stock/reserve',
  ah(async (req, res) => {
    await adjustStock(req.body.items || [], -1);
    log.info('stock reserved', { requestId: req.id, items: (req.body.items || []).length });
    res.json({ reserved: true });
  })
);

app.post(
  '/internal/stock/release',
  ah(async (req, res) => {
    await adjustStock(req.body.items || [], +1);
    log.info('stock released', { requestId: req.id });
    res.json({ released: true });
  })
);

start({
  port: PORT,
  init: async () => {
    pool = await initDatabase({ dbName: process.env.DB_NAME || 'catalog_db', migrations: MIGRATIONS, seed, log });
  },
  check: () => pool.query('SELECT 1'),
});
