import { Link } from 'react-router-dom';
import PickleJar from './PickleJar';
import { DietMark, SpiceMeter, Stars } from './Bits';
import { rupees } from '../api';
import { unitPrice } from '../pricing';
import { useCart } from '../context/CartContext';
import { useToast } from '../context/ToastContext';

export default function ProductCard({ product }) {
  const { add, busy } = useCart();
  const toast = useToast();

  const onAdd = async () => {
    try {
      await add(product.slug, '500g', 1);
      toast(`${product.name} (500g) added to cart`);
    } catch (e) {
      toast(e.message, 'error');
    }
  };

  return (
    <article className={`card product-card ${product.category}`}>
      {product.bestseller && <span className="badge-best">Bestseller</span>}
      <Link to={`/pickles/${product.slug}`} className="card-jar" aria-label={product.name}>
        <PickleJar product={product} size={132} />
      </Link>
      <div className="card-body">
        <div className="card-meta">
          <DietMark category={product.category} />
          <span className="region">{product.region}</span>
          <Stars rating={product.rating} />
        </div>
        <h3>
          <Link to={`/pickles/${product.slug}`}>{product.name}</Link>
        </h3>
        <p className="local">{product.localName}</p>
        <SpiceMeter level={product.spice} />
        <div className="card-foot">
          <div>
            <span className="price">{rupees(product.price500g)}</span>
            <span className="muted small"> / 500g</span>
            <div className="muted small">from {rupees(unitPrice(product.price500g, '250g'))}</div>
          </div>
          <button className="btn btn-add" onClick={onAdd} disabled={busy || !product.inStock}>
            {product.inStock ? 'Add' : 'Sold out'}
          </button>
        </div>
      </div>
    </article>
  );
}
