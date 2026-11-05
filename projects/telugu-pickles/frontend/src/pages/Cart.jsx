import { Link, useNavigate } from 'react-router-dom';
import { rupees } from '../api';
import PickleJar from '../components/PickleJar';
import { DietMark, QtyStepper } from '../components/Bits';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';

export function OrderSummary({ cart, children }) {
  const remaining = Math.max(0, cart.freeShippingThreshold - cart.subtotal);
  const pct = Math.min(100, (cart.subtotal / cart.freeShippingThreshold) * 100);
  return (
    <aside className="summary card">
      <h2>Order summary</h2>
      <div className="ship-progress">
        <div className="bar"><span style={{ width: `${pct}%` }} /></div>
        <p className="small">{remaining > 0 ? <>Add <strong>{rupees(remaining)}</strong> more for FREE shipping</> : <>🎉 You’ve unlocked <strong>free shipping</strong></>}</p>
      </div>
      <dl>
        <div><dt>Subtotal</dt><dd>{rupees(cart.subtotal)}</dd></div>
        <div><dt>Shipping</dt><dd>{cart.shipping === 0 ? <span className="free">FREE</span> : rupees(cart.shipping)}</dd></div>
        <div className="grand"><dt>Total</dt><dd>{rupees(cart.total)}</dd></div>
      </dl>
      {children}
    </aside>
  );
}

export default function Cart() {
  const { cart, setQty, busy } = useCart();
  const { user } = useAuth();
  const nav = useNavigate();
  const toast = useToast();

  const change = async (i, qty) => {
    try { await setQty(i.slug, i.weight, qty); } catch (e) { toast(e.message, 'error'); }
  };

  if (!cart.items.length) {
    return (
      <div className="container section empty-cart">
        <svg width="120" height="120" viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="32" r="30" fill="#E8F5E9" /><path d="M20 26h24v20c0 4-3 6-6 6H26c-3 0-6-2-6-6z" fill="#fff" stroke="#2E7D32" strokeWidth="2" /><path d="M18 20c0-6 28-6 28 0l1 6H17z" fill="#C62828" /></svg>
        <h1>Your cart is empty</h1>
        <p className="muted">Ammamma would not approve. Let’s fix that.</p>
        <Link to="/shop" className="btn btn-red btn-lg">Browse pickles</Link>
      </div>
    );
  }

  return (
    <div className="container section">
      <h1>Your cart</h1>
      <div className="cart-layout">
        <div className="cart-lines">
          {cart.items.map((i) => (
            <div className="cart-line card" key={`${i.slug}-${i.weight}`}>
              <Link to={`/pickles/${i.slug}`} className="cart-thumb"><PickleJar product={i} size={64} showLabel={false} /></Link>
              <div className="cart-info">
                <div className="card-meta"><DietMark category={i.category} /> <span className="muted small">{i.weight} pack</span></div>
                <Link to={`/pickles/${i.slug}`} className="cart-name">{i.name}</Link>
                <div className="local small">{i.localName}</div>
                <div className="muted small">{rupees(i.unitPrice)} each</div>
              </div>
              <QtyStepper value={i.qty} onChange={(q) => change(i, q)} disabled={busy} />
              <div className="cart-total">{rupees(i.lineTotal)}</div>
              <button className="remove" aria-label={`Remove ${i.name}`} onClick={() => change(i, 0)} disabled={busy}>✕</button>
            </div>
          ))}
        </div>
        <OrderSummary cart={cart}>
          <button className="btn btn-red btn-lg btn-block" onClick={() => nav(user ? '/checkout' : '/login?next=/checkout')}>
            {user ? 'Proceed to checkout' : 'Login to checkout'}
          </button>
          <Link to="/shop" className="continue">← Continue shopping</Link>
        </OrderSummary>
      </div>
    </div>
  );
}
