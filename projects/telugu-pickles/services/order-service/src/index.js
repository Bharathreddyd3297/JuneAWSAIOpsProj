// order-service — checkout orchestration + order history.
// Owns database: orders_db.
//
// Checkout is a small SAGA with compensation:
//   1. cart-service      GET  /cart                    (prices come from catalog, not the browser)
//   2. catalog-service   POST /internal/stock/reserve  (row-locked stock decrement)
//   3. orders_db         INSERT order (PENDING_PAYMENT)
//   4. payment-service   POST /internal/payments
//        ok      -> CONFIRMED, clear cart
//        failed  -> PAYMENT_FAILED, compensate: /internal/stock/release
const { createService, ah, HttpError } = require('../../common/service');
const { initDatabase } = require('../../common/db');
const { requireAuth } = require('../../common/auth');
const { callService } = require('../../common/http');
const { ordersPlacedTotal, orderValueRupeesTotal } = require('../../common/metrics');

const { app, log, start } = createService({ name: 'order-service' });
const PORT = Number(process.env.PORT || 4004);
const CART_URL = process.env.CART_SERVICE_URL || 'http://localhost:4003';
const CATALOG_URL = process.env.CATALOG_SERVICE_URL || 'http://localhost:4002';
const PAYMENT_URL = process.env.PAYMENT_SERVICE_URL || 'http://localhost:4005';
let pool;

const MIGRATIONS = [
  `CREATE TABLE IF NOT EXISTS orders (
     id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     order_number    VARCHAR(20)  NOT NULL UNIQUE,
     user_id         UUID         NOT NULL,
     status          VARCHAR(20)  NOT NULL,
     subtotal        INTEGER      NOT NULL,
     shipping        INTEGER      NOT NULL,
     total           INTEGER      NOT NULL,
     address         JSONB        NOT NULL,
     payment_method  VARCHAR(10)  NOT NULL,
     payment_status  VARCHAR(20),
     payment_ref     VARCHAR(40),
     created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
     updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
   )`,
  `CREATE TABLE IF NOT EXISTS order_items (
     id          SERIAL PRIMARY KEY,
     order_id    UUID         NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
     slug        VARCHAR(80)  NOT NULL,
     name        VARCHAR(120) NOT NULL,
     category    VARCHAR(10)  NOT NULL,
     color       VARCHAR(7),
     weight      VARCHAR(10)  NOT NULL,
     qty         SMALLINT     NOT NULL,
     unit_price  INTEGER      NOT NULL,
     line_total  INTEGER      NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id, created_at DESC)`,
];

function orderNumber() {
  const d = new Date();
  const ymd = `${String(d.getFullYear()).slice(2)}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  return `TP-${ymd}-${Math.floor(1000 + Math.random() * 9000)}${Math.floor(Math.random() * 10)}`;
}

function validateAddress(a) {
  const required = ['fullName', 'phone', 'line1', 'city', 'state', 'pincode'];
  const missing = required.filter((k) => !a || !String(a[k] || '').trim());
  if (missing.length) throw new HttpError(400, `Missing address fields: ${missing.join(', ')}`);
  if (!/^\d{6}$/.test(String(a.pincode))) throw new HttpError(400, 'PIN code must be 6 digits');
  if (!/^[6-9]\d{9}$/.test(String(a.phone))) throw new HttpError(400, 'Enter a valid 10-digit mobile number');
  return {
    fullName: a.fullName.trim(), phone: String(a.phone), line1: a.line1.trim(), line2: (a.line2 || '').trim(),
    city: a.city.trim(), state: a.state.trim(), pincode: String(a.pincode),
  };
}

async function loadOrders(whereSql, params) {
  const { rows: orders } = await pool.query(`SELECT * FROM orders ${whereSql} ORDER BY created_at DESC LIMIT 50`, params);
  if (!orders.length) return [];
  const { rows: items } = await pool.query('SELECT * FROM order_items WHERE order_id = ANY($1) ORDER BY id', [orders.map((o) => o.id)]);
  return orders.map((o) => ({
    id: o.id,
    orderNumber: o.order_number,
    status: o.status,
    subtotal: o.subtotal,
    shipping: o.shipping,
    total: o.total,
    address: o.address,
    paymentMethod: o.payment_method,
    paymentStatus: o.payment_status,
    paymentRef: o.payment_ref,
    createdAt: o.created_at,
    items: items
      .filter((i) => i.order_id === o.id)
      .map((i) => ({ slug: i.slug, name: i.name, category: i.category, color: i.color, weight: i.weight, qty: i.qty, unitPrice: i.unit_price, lineTotal: i.line_total })),
  }));
}

app.use('/orders', requireAuth);

app.post(
  '/orders',
  ah(async (req, res) => {
    const address = validateAddress(req.body?.address);
    const paymentMethod = String(req.body?.paymentMethod || 'UPI').toUpperCase();
    if (!['UPI', 'CARD', 'COD'].includes(paymentMethod)) throw new HttpError(400, 'Unsupported payment method');

    // 1. cart (authoritative prices)
    const cart = await callService('cart-service', `${CART_URL}/cart`, { req });
    if (!cart.items.length) throw new HttpError(400, 'Your cart is empty');
    const stockItems = cart.items.map((i) => ({ slug: i.slug, weight: i.weight, qty: i.qty }));

    // 2. reserve stock
    await callService('catalog-service', `${CATALOG_URL}/internal/stock/reserve`, { method: 'POST', body: { items: stockItems }, req });

    // 3. create order
    const c = await pool.connect();
    let order;
    try {
      await c.query('BEGIN');
      const { rows } = await c.query(
        `INSERT INTO orders (order_number,user_id,status,subtotal,shipping,total,address,payment_method)
         VALUES ($1,$2,'PENDING_PAYMENT',$3,$4,$5,$6,$7) RETURNING *`,
        [orderNumber(), req.user.id, cart.subtotal, cart.shipping, cart.total, address, paymentMethod]
      );
      order = rows[0];
      for (const i of cart.items) {
        await c.query(
          `INSERT INTO order_items (order_id,slug,name,category,color,weight,qty,unit_price,line_total)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
          [order.id, i.slug, i.name, i.category, i.color, i.weight, i.qty, i.unitPrice, i.lineTotal]
        );
      }
      await c.query('COMMIT');
    } catch (err) {
      await c.query('ROLLBACK');
      await callService('catalog-service', `${CATALOG_URL}/internal/stock/release`, { method: 'POST', body: { items: stockItems }, req }).catch(() => {});
      throw err;
    } finally {
      c.release();
    }

    // 4. payment
    let payment;
    let failure;
    try {
      payment = await callService('payment-service', `${PAYMENT_URL}/internal/payments`, {
        method: 'POST',
        body: { orderId: order.id, userId: req.user.id, amount: order.total, method: paymentMethod },
        req,
        timeoutMs: 10000,
      });
    } catch (err) {
      failure = err;
    }

    if (failure) {
      // compensation
      await pool.query(`UPDATE orders SET status='PAYMENT_FAILED', payment_status=$2, updated_at=now() WHERE id=$1`, [
        order.id,
        failure.status === 402 ? 'DECLINED' : 'ERROR',
      ]);
      await callService('catalog-service', `${CATALOG_URL}/internal/stock/release`, { method: 'POST', body: { items: stockItems }, req }).catch(
        (e) => log.error('stock release failed (needs reconciliation)', { requestId: req.id, orderId: order.id, error: e.message })
      );
      ordersPlacedTotal.inc({ status: 'PAYMENT_FAILED', payment_method: paymentMethod });
      log.error('checkout failed at payment step', {
        requestId: req.id, orderId: order.id, orderNumber: order.order_number, reason: failure.message, paymentStatus: failure.status,
      });
      if (failure.status === 402) throw new HttpError(402, 'Payment was declined by your bank. No money was deducted. Please try again or choose Cash on Delivery.');
      throw new HttpError(503, 'Payment service is unavailable right now. Please try again in a moment.');
    }

    await pool.query(
      `UPDATE orders SET status='CONFIRMED', payment_status=$2, payment_ref=$3, updated_at=now() WHERE id=$1`,
      [order.id, payment.status, payment.reference]
    );
    await callService('cart-service', `${CART_URL}/cart`, { method: 'DELETE', req }).catch((e) =>
      log.warn('could not clear cart after order', { requestId: req.id, error: e.message })
    );

    ordersPlacedTotal.inc({ status: 'CONFIRMED', payment_method: paymentMethod });
    orderValueRupeesTotal.inc(order.total);
    log.info('order confirmed', { requestId: req.id, orderId: order.id, orderNumber: order.order_number, total: order.total, paymentMethod });

    const [full] = await loadOrders('WHERE id = $1', [order.id]);
    res.status(201).json({ order: full });
  })
);

app.get('/orders', ah(async (req, res) => res.json({ orders: await loadOrders('WHERE user_id = $1', [req.user.id]) })));

app.get(
  '/orders/:id',
  ah(async (req, res) => {
    if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) throw new HttpError(404, 'Order not found');
    const [order] = await loadOrders('WHERE id = $1 AND user_id = $2', [req.params.id, req.user.id]);
    if (!order) throw new HttpError(404, 'Order not found');
    res.json({ order });
  })
);

app.post(
  '/orders/:id/cancel',
  ah(async (req, res) => {
    if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) throw new HttpError(404, 'Order not found');
    const [order] = await loadOrders('WHERE id = $1 AND user_id = $2', [req.params.id, req.user.id]);
    if (!order) throw new HttpError(404, 'Order not found');
    if (order.status !== 'CONFIRMED') throw new HttpError(409, `Order cannot be cancelled when ${order.status}`);
    await pool.query(`UPDATE orders SET status='CANCELLED', updated_at=now() WHERE id=$1`, [order.id]);
    await callService('catalog-service', `${CATALOG_URL}/internal/stock/release`, {
      method: 'POST',
      body: { items: order.items.map((i) => ({ slug: i.slug, weight: i.weight, qty: i.qty })) },
      req,
    });
    log.info('order cancelled', { requestId: req.id, orderId: order.id });
    const [updated] = await loadOrders('WHERE id = $1', [order.id]);
    res.json({ order: updated });
  })
);

start({
  port: PORT,
  init: async () => {
    pool = await initDatabase({ dbName: process.env.DB_NAME || 'orders_db', migrations: MIGRATIONS, log });
  },
  check: () => pool.query('SELECT 1'),
});
