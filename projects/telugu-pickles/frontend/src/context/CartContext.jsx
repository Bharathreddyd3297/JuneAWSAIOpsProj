import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { useAuth } from './AuthContext';
import { totals, unitPrice, FREE_SHIPPING_THRESHOLD } from '../pricing';

// Logged-in users: cart lives in cart-service (server).
// Guests: cart lives in localStorage and is merged into the server cart on login.
const GUEST_KEY = 'tp_guest_cart';
const EMPTY = { items: [], subtotal: 0, shipping: 0, total: 0, freeShippingThreshold: FREE_SHIPPING_THRESHOLD };

const readGuest = () => {
  try { return JSON.parse(localStorage.getItem(GUEST_KEY) || '[]'); } catch { return []; }
};
const writeGuest = (lines) => {
  try { localStorage.setItem(GUEST_KEY, JSON.stringify(lines)); } catch { /* ignore */ }
};

const CartContext = createContext(null);

export function CartProvider({ children }) {
  const { user, loading: authLoading } = useAuth();
  const [cart, setCart] = useState(EMPTY);
  const [busy, setBusy] = useState(false);

  const buildGuestCart = useCallback(async (lines) => {
    if (!lines.length) return EMPTY;
    const slugs = [...new Set(lines.map((l) => l.slug))].join(',');
    const { products } = await api(`/products?slugs=${encodeURIComponent(slugs)}`);
    const by = Object.fromEntries(products.map((p) => [p.slug, p]));
    const items = lines
      .filter((l) => by[l.slug])
      .map((l) => {
        const p = by[l.slug];
        const price = unitPrice(p.price500g, l.weight);
        return { ...l, name: p.name, localName: p.localName, category: p.category, color: p.color, unitPrice: price, lineTotal: price * l.qty, inStock: p.inStock };
      });
    return { items, ...totals(items), freeShippingThreshold: FREE_SHIPPING_THRESHOLD };
  }, []);

  const refresh = useCallback(async () => {
    try {
      setCart(user ? await api('/cart') : await buildGuestCart(readGuest()));
    } catch {
      /* keep previous cart on transient errors */
    }
  }, [user, buildGuestCart]);

  // On login: merge guest cart into server cart once.
  useEffect(() => {
    if (authLoading) return;
    (async () => {
      const guest = readGuest();
      if (user && guest.length) {
        try {
          setCart(await api('/cart/merge', { method: 'POST', body: { items: guest } }));
          writeGuest([]);
          return;
        } catch { /* fall through */ }
      }
      refresh();
    })();
  }, [user, authLoading, refresh]);

  const mutateGuest = useCallback(
    async (fn) => {
      const lines = fn(readGuest()).filter((l) => l.qty > 0);
      writeGuest(lines);
      setCart(await buildGuestCart(lines));
    },
    [buildGuestCart]
  );

  const add = useCallback(
    async (slug, weight = '500g', qty = 1) => {
      setBusy(true);
      try {
        if (user) setCart(await api('/cart/items', { method: 'POST', body: { slug, weight, qty } }));
        else
          await mutateGuest((lines) => {
            const hit = lines.find((l) => l.slug === slug && l.weight === weight);
            if (hit) hit.qty = Math.min(hit.qty + qty, 10);
            else lines.push({ slug, weight, qty });
            return lines;
          });
      } finally {
        setBusy(false);
      }
    },
    [user, mutateGuest]
  );

  const setQty = useCallback(
    async (slug, weight, qty) => {
      setBusy(true);
      try {
        if (user) setCart(await api('/cart/items', { method: 'PUT', body: { slug, weight, qty } }));
        else
          await mutateGuest((lines) => {
            const hit = lines.find((l) => l.slug === slug && l.weight === weight);
            if (hit) hit.qty = qty;
            return lines;
          });
      } finally {
        setBusy(false);
      }
    },
    [user, mutateGuest]
  );

  const count = cart.items.reduce((n, i) => n + i.qty, 0);
  const value = useMemo(() => ({ cart, count, busy, add, setQty, refresh, setCart }), [cart, count, busy, add, setQty, refresh]);
  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export const useCart = () => useContext(CartContext);
