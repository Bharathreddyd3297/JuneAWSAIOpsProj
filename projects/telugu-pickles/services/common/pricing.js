// Pricing rules live in ONE place so cart, order and frontend agree.
// Catalog stores price_500g in whole rupees; other pack sizes are derived.
const WEIGHTS = {
  '250g': 0.55,
  '500g': 1,
  '1kg': 1.9,
};

const FREE_SHIPPING_THRESHOLD = 999; // INR
const SHIPPING_FEE = 79; // INR

function unitPrice(price500g, weight) {
  const factor = WEIGHTS[weight];
  if (!factor) throw new Error(`Unsupported pack size: ${weight}`);
  return Math.round(price500g * factor);
}

function shippingFor(subtotal) {
  if (subtotal <= 0) return 0;
  return subtotal >= FREE_SHIPPING_THRESHOLD ? 0 : SHIPPING_FEE;
}

function totals(lines) {
  const subtotal = lines.reduce((s, l) => s + l.unitPrice * l.qty, 0);
  const shipping = shippingFor(subtotal);
  return { subtotal, shipping, total: subtotal + shipping };
}

module.exports = { WEIGHTS, FREE_SHIPPING_THRESHOLD, SHIPPING_FEE, unitPrice, shippingFor, totals };
