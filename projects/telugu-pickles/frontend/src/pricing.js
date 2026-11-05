// Mirrors services/common/pricing.js (server is authoritative; this is for display + guest cart)
export const WEIGHTS = { '250g': 0.55, '500g': 1, '1kg': 1.9 };
export const PACKS = Object.keys(WEIGHTS);
export const FREE_SHIPPING_THRESHOLD = 999;
export const SHIPPING_FEE = 79;

export const unitPrice = (price500g, weight) => Math.round(price500g * WEIGHTS[weight]);

export function totals(items) {
  const subtotal = items.reduce((s, i) => s + i.unitPrice * i.qty, 0);
  const shipping = subtotal === 0 || subtotal >= FREE_SHIPPING_THRESHOLD ? 0 : SHIPPING_FEE;
  return { subtotal, shipping, total: subtotal + shipping };
}
