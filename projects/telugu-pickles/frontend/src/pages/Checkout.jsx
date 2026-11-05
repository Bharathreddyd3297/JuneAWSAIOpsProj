import { useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { api } from '../api';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import { OrderSummary } from './Cart';

const STATES = ['Andhra Pradesh', 'Telangana', 'Karnataka', 'Tamil Nadu', 'Kerala', 'Maharashtra', 'Delhi', 'Gujarat', 'West Bengal', 'Uttar Pradesh', 'Other'];
const METHODS = [
  { id: 'UPI', title: 'UPI', text: 'PhonePe, Google Pay, Paytm, BHIM' },
  { id: 'CARD', title: 'Credit / Debit card', text: 'Visa, Mastercard, RuPay' },
  { id: 'COD', title: 'Cash on Delivery', text: 'Pay when your pickles arrive' },
];

export default function Checkout() {
  const { user } = useAuth();
  const { cart, refresh } = useCart();
  const nav = useNavigate();
  const [address, setAddress] = useState({
    fullName: user?.name || '', phone: user?.phone || '', line1: '', line2: '', city: 'Hyderabad', state: 'Telangana', pincode: '',
  });
  const [method, setMethod] = useState('UPI');
  const [error, setError] = useState('');
  const [placing, setPlacing] = useState(false);

  if (!user) return <Navigate to="/login?next=/checkout" replace />;
  if (!cart.items.length && !placing) return <Navigate to="/cart" replace />;

  const upd = (k) => (e) => setAddress((a) => ({ ...a, [k]: e.target.value }));

  const place = async (e) => {
    e.preventDefault();
    setError('');
    setPlacing(true);
    try {
      const { order } = await api('/orders', { method: 'POST', body: { address, paymentMethod: method } });
      await refresh();
      nav(`/orders/${order.id}?placed=1`, { replace: true });
    } catch (err) {
      setError(err.message);
      setPlacing(false);
    }
  };

  return (
    <div className="container section">
      <h1>Checkout</h1>
      <form className="cart-layout" onSubmit={place}>
        <div className="checkout-main">
          <section className="card form-card">
            <h2><span className="step">1</span> Delivery address</h2>
            <div className="form-grid">
              <label>Full name<input required value={address.fullName} onChange={upd('fullName')} autoComplete="name" /></label>
              <label>Mobile number<input required value={address.phone} onChange={upd('phone')} inputMode="numeric" pattern="[6-9][0-9]{9}" title="10-digit Indian mobile number" autoComplete="tel" /></label>
              <label className="span-2">House / street<input required value={address.line1} onChange={upd('line1')} autoComplete="address-line1" /></label>
              <label className="span-2">Area / landmark (optional)<input value={address.line2} onChange={upd('line2')} autoComplete="address-line2" /></label>
              <label>City<input required value={address.city} onChange={upd('city')} autoComplete="address-level2" /></label>
              <label>State<select value={address.state} onChange={upd('state')}>{STATES.map((s) => <option key={s}>{s}</option>)}</select></label>
              <label>PIN code<input required value={address.pincode} onChange={upd('pincode')} inputMode="numeric" pattern="[0-9]{6}" title="6-digit PIN code" autoComplete="postal-code" /></label>
            </div>
          </section>
          <section className="card form-card">
            <h2><span className="step">2</span> Payment</h2>
            <div className="methods">
              {METHODS.map((m) => (
                <label key={m.id} className={`method ${method === m.id ? 'active' : ''}`}>
                  <input type="radio" name="method" value={m.id} checked={method === m.id} onChange={() => setMethod(m.id)} />
                  <span><strong>{m.title}</strong><span className="muted small">{m.text}</span></span>
                </label>
              ))}
            </div>
            <p className="muted small">Demo store: payments are simulated by payment-service. No money is charged.</p>
          </section>
          {error && <div className="alert alert-error">{error}</div>}
        </div>
        <OrderSummary cart={cart}>
          <button type="submit" className="btn btn-green btn-lg btn-block" disabled={placing}>
            {placing ? 'Placing order…' : method === 'COD' ? 'Place order (COD)' : 'Pay & place order'}
          </button>
          <Link to="/cart" className="continue">← Back to cart</Link>
        </OrderSummary>
      </form>
    </div>
  );
}
