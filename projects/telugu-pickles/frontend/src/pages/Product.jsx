import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, rupees } from '../api';
import PickleJar from '../components/PickleJar';
import ProductCard from '../components/ProductCard';
import { DietMark, QtyStepper, SpiceMeter, Spinner, Stars } from '../components/Bits';
import { PACKS, unitPrice } from '../pricing';
import { useCart } from '../context/CartContext';
import { useToast } from '../context/ToastContext';

export default function Product() {
  const { slug } = useParams();
  const [product, setProduct] = useState(null);
  const [related, setRelated] = useState([]);
  const [error, setError] = useState('');
  const [pack, setPack] = useState('500g');
  const [qty, setQty] = useState(1);
  const { add, busy } = useCart();
  const toast = useToast();

  useEffect(() => {
    setProduct(null);
    setError('');
    setQty(1);
    api(`/products/${slug}`)
      .then((d) => {
        setProduct(d.product);
        return api(`/products?category=${d.product.category}&sort=rating`);
      })
      .then((d) => setRelated(d.products.filter((p) => p.slug !== slug).slice(0, 4)))
      .catch((e) => setError(e.message));
  }, [slug]);

  if (error) return <div className="container section"><div className="alert alert-error">{error}</div><Link to="/shop">← Back to all pickles</Link></div>;
  if (!product) return <div className="container section"><Spinner /></div>;

  const price = unitPrice(product.price500g, pack);
  const onAdd = async () => {
    try {
      await add(product.slug, pack, qty);
      toast(`${qty} × ${product.name} (${pack}) added to cart`);
    } catch (e) {
      toast(e.message, 'error');
    }
  };

  return (
    <div className="container section">
      <nav className="crumbs">
        <Link to="/">Home</Link> / <Link to={`/shop?category=${product.category}`}>{product.category === 'veg' ? 'Veg Pickles' : 'Non-Veg Pickles'}</Link> / <span>{product.name}</span>
      </nav>
      <div className={`pdp ${product.category}`}>
        <div className="pdp-art">
          <PickleJar product={product} size={300} />
        </div>
        <div className="pdp-info">
          <div className="card-meta">
            <DietMark category={product.category} size={20} />
            <span className="region">{product.region}</span>
            {product.bestseller && <span className="badge-inline">Bestseller</span>}
          </div>
          <h1>{product.name}</h1>
          <p className="pdp-te">{product.localName}</p>
          <div className="pdp-rating">
            <Stars rating={product.rating} reviews={product.reviews} /> <span className="muted">reviews</span>
            <span className="dot">·</span> <SpiceMeter level={product.spice} /> <span className="muted small">spice</span>
          </div>
          <p className="pdp-desc">{product.description}</p>

          <div className="pdp-buy">
            <div className="pack-label">Choose pack size</div>
            <div className="packs">
              {PACKS.map((p) => (
                <button key={p} className={`pack ${pack === p ? 'active' : ''}`} onClick={() => setPack(p)}>
                  <strong>{p}</strong>
                  <span>{rupees(unitPrice(product.price500g, p))}</span>
                </button>
              ))}
            </div>
            <div className="buy-row">
              <QtyStepper value={qty} onChange={setQty} />
              <button className="btn btn-red btn-lg" onClick={onAdd} disabled={busy || !product.inStock}>
                {product.inStock ? `Add to cart · ${rupees(price * qty)}` : 'Sold out'}
              </button>
            </div>
          </div>

          <dl className="facts">
            <div><dt>Ingredients</dt><dd>{product.ingredients}</dd></div>
            <div><dt>Shelf life</dt><dd>{product.shelfLifeDays >= 365 ? '12 months' : `${Math.round(product.shelfLifeDays / 30)} months`}{product.category === 'non-veg' ? ' · refrigerate after opening' : ' · store in a cool, dry place'}</dd></div>
            <div><dt>Tip</dt><dd>Always use a dry spoon. Best with hot rice, ghee and a little dal.</dd></div>
          </dl>
        </div>
      </div>

      {related.length > 0 && (
        <section className="section">
          <div className="section-head"><h2>You may also like</h2></div>
          <div className="grid">
            {related.map((p) => <ProductCard key={p.slug} product={p} />)}
          </div>
        </section>
      )}
    </div>
  );
}
