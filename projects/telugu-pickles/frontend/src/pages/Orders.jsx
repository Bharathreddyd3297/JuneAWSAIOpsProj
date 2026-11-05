import { useEffect, useState } from 'react';
import { Link, Navigate, useParams, useSearchParams } from 'react-router-dom';
import { api, rupees } from '../api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import PickleJar from '../components/PickleJar';
import { Spinner } from '../components/Bits';

const STATUS_LABEL = {
  CONFIRMED: 'Confirmed',
  PAYMENT_FAILED: 'Payment failed',
  PENDING_PAYMENT: 'Awaiting payment',
  CANCELLED: 'Cancelled',
};

export const StatusBadge = ({ status }) => <span className={`status status-${status.toLowerCase()}`}>{STATUS_LABEL[status] || status}</span>;
const date = (d) => new Date(d).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export function Orders() {
  const { user, loading } = useAuth();
  const [orders, setOrders] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (user) api('/orders').then((d) => setOrders(d.orders)).catch((e) => setError(e.message));
  }, [user]);

  if (!loading && !user) return <Navigate to="/login?next=/orders" replace />;
  return (
    <div className="container section">
      <h1>My orders</h1>
      {error && <div className="alert alert-error">{error}</div>}
      {!orders ? <Spinner /> : orders.length === 0 ? (
        <div className="empty"><p>No orders yet.</p><Link to="/shop" className="btn btn-red">Start shopping</Link></div>
      ) : (
        <div className="order-list">
          {orders.map((o) => (
            <Link to={`/orders/${o.id}`} key={o.id} className="card order-row">
              <div className="order-jars">
                {o.items.slice(0, 3).map((i) => <PickleJar key={i.slug + i.weight} product={i} size={40} showLabel={false} />)}
              </div>
              <div className="order-main">
                <strong>{o.orderNumber}</strong>
                <span className="muted small">{date(o.createdAt)} · {o.items.reduce((n, i) => n + i.qty, 0)} jars</span>
              </div>
              <StatusBadge status={o.status} />
              <strong className="order-amt">{rupees(o.total)}</strong>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

export function OrderDetail() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const { user, loading } = useAuth();
  const toast = useToast();
  const [order, setOrder] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (user) api(`/orders/${id}`).then((d) => setOrder(d.order)).catch((e) => setError(e.message));
  }, [id, user]);

  if (!loading && !user) return <Navigate to="/login" replace />;
  if (error) return <div className="container section"><div className="alert alert-error">{error}</div></div>;
  if (!order) return <div className="container section"><Spinner /></div>;

  const cancel = async () => {
    if (!window.confirm('Cancel this order?')) return;
    try {
      const d = await api(`/orders/${order.id}/cancel`, { method: 'POST' });
      setOrder(d.order);
      toast('Order cancelled');
    } catch (e) {
      toast(e.message, 'error');
    }
  };

  return (
    <div className="container section">
      {params.get('placed') && order.status === 'CONFIRMED' && (
        <div className="success-banner">
          <div className="success-icon">✓</div>
          <div>
            <h1>Dhanyavadalu! Your order is confirmed.</h1>
            <p>ధన్యవాదాలు · We’ll start packing your pickles fresh today.</p>
          </div>
        </div>
      )}
      <div className="order-head">
        <div>
          <h2>Order {order.orderNumber}</h2>
          <span className="muted">{date(order.createdAt)}</span>
        </div>
        <StatusBadge status={order.status} />
      </div>
      <div className="cart-layout">
        <div className="card">
          {order.items.map((i) => (
            <div className="order-item" key={i.slug + i.weight}>
              <PickleJar product={i} size={48} showLabel={false} />
              <div className="grow">
                <Link to={`/pickles/${i.slug}`}><strong>{i.name}</strong></Link>
                <div className="muted small">{i.weight} × {i.qty} · {rupees(i.unitPrice)} each</div>
              </div>
              <strong>{rupees(i.lineTotal)}</strong>
            </div>
          ))}
        </div>
        <aside className="summary card">
          <h2>Details</h2>
          <dl>
            <div><dt>Subtotal</dt><dd>{rupees(order.subtotal)}</dd></div>
            <div><dt>Shipping</dt><dd>{order.shipping ? rupees(order.shipping) : <span className="free">FREE</span>}</dd></div>
            <div className="grand"><dt>Total</dt><dd>{rupees(order.total)}</dd></div>
            <div><dt>Payment</dt><dd>{order.paymentMethod} · {order.paymentStatus || '—'}</dd></div>
            {order.paymentRef && <div><dt>Reference</dt><dd className="mono small">{order.paymentRef}</dd></div>}
          </dl>
          <div className="addr">
            <strong>Deliver to</strong>
            <p>{order.address.fullName}, {order.address.phone}<br />{order.address.line1}{order.address.line2 ? `, ${order.address.line2}` : ''}<br />{order.address.city}, {order.address.state} – {order.address.pincode}</p>
          </div>
          {order.status === 'CONFIRMED' && <button className="btn btn-outline btn-block" onClick={cancel}>Cancel order</button>}
          <Link to="/orders" className="continue">← All orders</Link>
        </aside>
      </div>
    </div>
  );
}
