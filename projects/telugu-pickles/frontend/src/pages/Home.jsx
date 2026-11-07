import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api';
import PickleJar from '../components/PickleJar';
import ProductCard from '../components/ProductCard';
import { DietMark, Spinner } from '../components/Bits';

const HERO_JARS = [
  { slug: 'avakaya', name: 'Avakaya', localName: 'ఆవకాయ', category: 'veg', color: '#B5381F' },
  { slug: 'gongura-mutton', name: 'Gongura Mutton', localName: 'గోంగూర మటన్', category: 'non-veg', color: '#4E3418' },
  { slug: 'gongura', name: 'Gongura', localName: 'గోంగూర', category: 'veg', color: '#4E5A23' },
];

const PROMISES = [
  { icon: '🥜', title: 'Cold-pressed Olive oil', text: 'Every jar is made with wood-pressed oil from Anantapur groundnuts.' },
  { icon: '🌶️', title: 'Kashmiri chillies, sun-dried', text: 'We dry and pound our own chillies and mustard — no ready masalas.' },
  { icon: '🏺', title: 'Matured in jaadis', text: 'Mango pickles rest in ceramic jaadis for 21 days, the way Ammamma made them.' },
  { icon: '🚫', title: 'No artificial preservatives', text: 'Only salt, oil and spices. Just like home.' },
];

export default function Home() {
  const [best, setBest] = useState(null);
  const [cats, setCats] = useState([]);

  useEffect(() => {
    api('/products?bestseller=true&sort=popular').then((d) => setBest(d.products)).catch(() => setBest([]));
    api('/categories').then((d) => setCats(d.categories)).catch(() => {});
  }, []);
  const count = (id) => cats.find((c) => c.id === id)?.count ?? '';

  return (
    <>
      <section className="hero">
        <div className="container hero-grid">
          <div className="hero-copy">
            <p className="hero-te">అమ్మ చేతి రుచి</p>
            <h1>
              ANy kind of pickles are available,
              <br /> <span>made the Amma way.</span>
            </h1>
            <p className="hero-sub">
              From fiery Guntur Avakaya to Godavari prawn pickle — hand-made in small batches with cold-pressed oil and
              sun-dried spices, delivered fresh across India.
            </p>
            <div className="hero-ctas">
              <Link to="/shop?category=veg" className="btn btn-green btn-lg">Shop Veg Pickles</Link>
              <Link to="/shop?category=non-veg" className="btn btn-light btn-lg">Shop Non-Veg Pickles</Link>
            </div>
            <ul className="hero-stats">
              <li><strong>36+</strong> traditional recipes</li>
              <li><strong>4.6★</strong> from 9,000+ families</li>
              <li><strong>21 days</strong> jaadi-matured</li>
            </ul>
          </div>
          <div className="hero-jars" aria-hidden="true">
            {HERO_JARS.map((j, i) => (
              <div key={j.slug} className={`hero-jar hero-jar-${i}`}>
                <PickleJar product={j} size={i === 1 ? 210 : 160} />
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="container section">
        <div className="cat-grid">
          <Link to="/shop?category=veg" className="cat-card cat-veg">
            <DietMark category="veg" size={22} />
            <h2>Veg Pickles</h2>
            <p className="cat-te">శాకాహార పచ్చళ్ళు</p>
            <p>Avakaya, Gongura, Magaya, Usirikaya, Pandu Mirapakaya and more.</p>
            <span className="cat-link">{count('veg')} pickles →</span>
          </Link>
          <Link to="/shop?category=non-veg" className="cat-card cat-nonveg">
            <DietMark category="non-veg" size={22} />
            <h2>Non-Veg Pickles</h2>
            <p className="cat-te">మాంసాహార పచ్చళ్ళు</p>
            <p>Chicken, Natu Kodi, Mutton, Gongura Mutton, Prawns, Fish and Crab.</p>
            <span className="cat-link">{count('non-veg')} pickles →</span>
          </Link>
        </div>
      </section>

      <section className="container section">
        <div className="section-head">
          <h2>Bestsellers</h2>
          <Link to="/shop?bestseller=true" className="see-all">See all →</Link>
        </div>
        {best === null ? <Spinner /> : (
          <div className="grid">
            {best.map((p) => <ProductCard key={p.slug} product={p} />)}
          </div>
        )}
      </section>

      <section className="promise">
        <div className="container">
          <h2>Why families trust Telugu Pickles</h2>
          <div className="promise-grid">
            {PROMISES.map((p) => (
              <div className="promise-item" key={p.title}>
                <div className="promise-icon">{p.icon}</div>
                <h3>{p.title}</h3>
                <p>{p.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="container section regions">
        <h2>Pickles from every corner</h2>
        <div className="chips">
          {['Guntur', 'Godavari', 'Coastal Andhra', 'Telangana', 'Rayalaseema', 'Hyderabad', 'Nellore', 'Kerala', 'Punjab', 'Gujarat', 'Rajasthan', 'Goa', 'Coorg'].map((r) => (
            <Link key={r} className="chip" to={`/shop?region=${encodeURIComponent(r)}`}>{r}</Link>
          ))}
        </div>
      </section>
    </>
  );
}
