import { useEffect, useState } from 'react';
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useCart } from '../context/CartContext';
import { FREE_SHIPPING_THRESHOLD } from '../pricing';
import { rupees } from '../api';

function Logo() {
  return (
    <Link to="/" className="logo" aria-label="Telugu Pickles home">
      <svg width="44" height="44" viewBox="0 0 64 64" aria-hidden="true">
        <circle cx="32" cy="32" r="31" fill="#C62828" />
        <path d="M20 24h24v3c4 2 5 6 5 11v10c0 4-3 7-7 7H22c-4 0-7-3-7-7V38c0-5 1-9 5-11z" fill="#FFF9F0" />
        <path d="M16 22c0-8 32-8 32 0l2 5c-3 2-6 2-9 0-3 2-6 2-9 0-3 2-6 2-9 0-3 2-6 2-9 0z" fill="#2E7D32" />
        <path d="M18 40h28v8c0 3-2 5-5 5H23c-3 0-5-2-5-5z" fill="#B5381F" />
      </svg>
      <span className="logo-text">
        <span className="logo-en">Telugu Pickles</span>
        <span className="logo-te">తెలుగు పచ్చళ్ళు</span>
      </span>
    </Link>
  );
}

function Header() {
  const { user, logout } = useAuth();
  const { count } = useCart();
  const nav = useNavigate();
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const loc = useLocation();
  useEffect(() => {
    setOpen(false);
  }, [loc.pathname, loc.search]);

  const submit = (e) => {
    e.preventDefault();
    nav(`/shop${q.trim() ? `?q=${encodeURIComponent(q.trim())}` : ''}`);
  };

  return (
    <header className="site-header">
      <div className="topbar">
        <span>🚚 Free shipping on orders above {rupees(FREE_SHIPPING_THRESHOLD)}</span>
        <span className="hide-sm">Made fresh in small batches · Guntur · Godavari · Hyderabad</span>
      </div>
      <div className="header-main container">
        <Logo />
        <form className="search" onSubmit={submit} role="search">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search avakaya, gongura, prawns…" aria-label="Search pickles" />
          <button type="submit" aria-label="Search">
            <svg width="18" height="18" viewBox="0 0 24 24"><path d="M10 2a8 8 0 105.3 14l5.4 5.3 1.4-1.4-5.3-5.4A8 8 0 0010 2zm0 2a6 6 0 110 12 6 6 0 010-12z" fill="currentColor" /></svg>
          </button>
        </form>
        <div className="header-actions">
          {user ? (
            <div className="user-menu">
              <span className="hello hide-sm">Namaskaram, {user.name.split(' ')[0]}</span>
              <button className="link-btn" onClick={logout}>Logout</button>
            </div>
          ) : (
            <Link to="/login" className="link-btn">Login</Link>
          )}
          <Link to="/cart" className="cart-btn" aria-label={`Cart with ${count} items`}>
            <svg width="22" height="22" viewBox="0 0 24 24"><path d="M7 18a2 2 0 100 4 2 2 0 000-4zm10 0a2 2 0 100 4 2 2 0 000-4zM5.2 4l.6 3H21l-2 8H7.4L4.4 2H1v2h3.2z" fill="currentColor" /></svg>
            <span>Cart</span>
            {count > 0 && <span className="cart-count">{count}</span>}
          </Link>
          <button className="menu-toggle" aria-label="Menu" onClick={() => setOpen((o) => !o)}>☰</button>
        </div>
      </div>
      <nav className={`main-nav ${open ? 'open' : ''}`}>
        <div className="container">
          <NavLink to="/" end>Home</NavLink>
          <NavLink to="/shop?category=veg" className="nav-veg">Veg Pickles</NavLink>
          <NavLink to="/shop?category=non-veg" className="nav-nonveg">Non-Veg Pickles</NavLink>
          <NavLink to="/shop?bestseller=true">Bestsellers</NavLink>
          <NavLink to="/shop">All Pickles</NavLink>
          <NavLink to="/orders">My Orders</NavLink>
        </div>
      </nav>
    </header>
  );
}

function Footer() {
  return (
    <footer className="site-footer">
      <div className="container footer-grid">
        <div>
          <div className="footer-brand">Telugu Pickles</div>
          <p className="footer-te">అమ్మ చేతి రుచి — the taste of Amma’s hands.</p>
          <p className="small">Traditional Andhra &amp; Telangana pickles made with cold-pressed groundnut oil, sun-dried spices and no artificial preservatives.</p>
        </div>
        <div>
          <h4>Shop</h4>
          <Link to="/shop?category=veg">Veg Pickles</Link>
          <Link to="/shop?category=non-veg">Non-Veg Pickles</Link>
          <Link to="/shop?bestseller=true">Bestsellers</Link>
        </div>
        <div>
          <h4>Help</h4>
          <Link to="/orders">Track my order</Link>
          <span>Shipping across India in 3–6 days</span>
          <span>care@telugupickles.in</span>
        </div>
        <div>
          <h4>Promise</h4>
          <span>✔ FSSAI-style hygienic kitchen</span>
          <span>✔ Leak-proof double-sealed jars</span>
          <span>✔ Small batches, made to order</span>
        </div>
      </div>
      <div className="footer-bottom">© {new Date().getFullYear()} Telugu Pickles · Demo store for a DevOps + AIOps project — no real payments are taken.</div>
    </footer>
  );
}

export default function Layout() {
  const { pathname } = useLocation();
  // Block body on purpose: newer browsers return a Promise from scrollTo, and React
  // treats any returned value as a cleanup function ("destroy is not a function").
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);
  return (
    <>
      <Header />
      <main>
        <Outlet />
      </main>
      <Footer />
    </>
  );
}
