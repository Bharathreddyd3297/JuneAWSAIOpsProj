const test = require('node:test');
const assert = require('node:assert');
const { unitPrice, shippingFor, totals, FREE_SHIPPING_THRESHOLD, SHIPPING_FEE } = require('../common/pricing');
const products = require('../catalog-service/src/products');

test('unit price per pack size', () => {
  assert.strictEqual(unitPrice(349, '500g'), 349);
  assert.strictEqual(unitPrice(349, '250g'), 192);
  assert.strictEqual(unitPrice(349, '1kg'), 663);
  assert.throws(() => unitPrice(349, '2kg'));
});

test('free shipping threshold', () => {
  assert.strictEqual(shippingFor(0), 0);
  assert.strictEqual(shippingFor(FREE_SHIPPING_THRESHOLD - 1), SHIPPING_FEE);
  assert.strictEqual(shippingFor(FREE_SHIPPING_THRESHOLD), 0);
});

test('cart totals', () => {
  const t = totals([{ unitPrice: 349, qty: 2 }, { unitPrice: 299, qty: 1 }]);
  assert.deepStrictEqual(t, { subtotal: 997, shipping: SHIPPING_FEE, total: 997 + SHIPPING_FEE });
});

test('catalogue has veg and non-veg pickles with unique slugs', () => {
  const slugs = new Set(products.map((p) => p.slug));
  assert.strictEqual(slugs.size, products.length);
  assert.ok(products.filter((p) => p.category === 'veg').length >= 15);
  assert.ok(products.filter((p) => p.category === 'non-veg').length >= 12);
  for (const p of products) {
    assert.match(p.color, /^#[0-9A-Fa-f]{6}$/);
    assert.ok(p.spice >= 1 && p.spice <= 5);
    assert.ok(p.price500g > 0);
  }
});
