import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import PickleJar from '../components/PickleJar';

function AuthShell({ title, te, children }) {
  return (
    <div className="container section auth-wrap">
      <div className="auth-art">
        <PickleJar product={{ slug: 'auth', name: 'Avakaya', localName: 'ఆవకాయ', category: 'veg', color: '#B5381F' }} size={150} />
        <PickleJar product={{ slug: 'auth2', name: 'Royyala', localName: 'రొయ్యల పచ్చడి', category: 'non-veg', color: '#B0451E' }} size={120} />
      </div>
      <div className="card auth-card">
        <h1>{title}</h1>
        <p className="muted">{te}</p>
        {children}
      </div>
    </div>
  );
}

export function Login() {
  const { login } = useAuth();
  const toast = useToast();
  const nav = useNavigate();
  const [params] = useSearchParams();
  const [form, setForm] = useState({ email: '', password: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      const u = await login(form.email, form.password);
      toast(`Namaskaram, ${u.name.split(' ')[0]}!`);
      nav(params.get('next') || '/', { replace: true });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell title="Welcome back" te="తిరిగి స్వాగతం">
      <form onSubmit={submit} className="stack">
        <label>Email<input type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} autoComplete="email" /></label>
        <label>Password<input type="password" required value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} autoComplete="current-password" /></label>
        {error && <div className="alert alert-error">{error}</div>}
        <button className="btn btn-red btn-lg btn-block" disabled={busy}>{busy ? 'Logging in…' : 'Login'}</button>
        <button type="button" className="btn btn-outline btn-block" onClick={() => setForm({ email: 'demo@telugupickles.in', password: 'Pickle@123' })}>
          Use demo account
        </button>
        <p className="center small">New here? <Link to={`/register${params.get('next') ? `?next=${params.get('next')}` : ''}`}>Create an account</Link></p>
      </form>
    </AuthShell>
  );
}

export function Register() {
  const { register } = useAuth();
  const toast = useToast();
  const nav = useNavigate();
  const [params] = useSearchParams();
  const [form, setForm] = useState({ name: '', email: '', phone: '', password: '' });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const upd = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const submit = async (e) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      const u = await register(form);
      toast(`Welcome to Telugu Pickles, ${u.name.split(' ')[0]}!`);
      nav(params.get('next') || '/', { replace: true });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell title="Create your account" te="ఖాతా సృష్టించండి">
      <form onSubmit={submit} className="stack">
        <label>Full name<input required value={form.name} onChange={upd('name')} autoComplete="name" /></label>
        <label>Email<input type="email" required value={form.email} onChange={upd('email')} autoComplete="email" /></label>
        <label>Mobile (optional)<input value={form.phone} onChange={upd('phone')} inputMode="numeric" autoComplete="tel" /></label>
        <label>Password<input type="password" required minLength={8} value={form.password} onChange={upd('password')} autoComplete="new-password" /></label>
        {error && <div className="alert alert-error">{error}</div>}
        <button className="btn btn-green btn-lg btn-block" disabled={busy}>{busy ? 'Creating…' : 'Create account'}</button>
        <p className="center small">Already have an account? <Link to="/login">Login</Link></p>
      </form>
    </AuthShell>
  );
}
