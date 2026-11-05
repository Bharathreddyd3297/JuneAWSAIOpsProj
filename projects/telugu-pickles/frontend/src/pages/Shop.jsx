import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../api';
import ProductCard from '../components/ProductCard';
import { Spinner } from '../components/Bits';

const SORTS = [
  ['popular', 'Most popular'],
  ['rating', 'Top rated'],
  ['price-asc', 'Price: low to high'],
  ['price-desc', 'Price: high to low'],
  ['spice', 'Spiciest first'],
];

export default function Shop() {
  const [params, setParams] = useSearchParams();
  const [products, setProducts] = useState(null);
  const [regions, setRegions] = useState([]);
  const [error, setError] = useState('');

  const category = params.get('category') || '';
  const region = params.get('region') || '';
  const maxSpice = params.get('maxSpice') || '';
  const sort = params.get('sort') || 'popular';
  const q = params.get('q') || '';
  const bestseller = params.get('bestseller') || '';

  useEffect(() => {
    api('/regions').then((d) => setRegions(d.regions)).catch(() => {});
  }, []);

  useEffect(() => {
    setProducts(null);
    setError('');
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries({ category, region, maxSpice, sort, q, bestseller })) if (v) qs.set(k, v);
    api(`/products?${qs}`)
      .then((d) => setProducts(d.products))
      .catch((e) => { setError(e.message); setProducts([]); });
  }, [category, region, maxSpice, sort, q, bestseller]);

  const set = (k, v) => {
    const next = new URLSearchParams(params);
    if (v) next.set(k, v); else next.delete(k);
    setParams(next);
  };

  const title = q ? `Results for “${q}”`
    : bestseller ? 'Bestsellers'
    : category === 'veg' ? 'Veg Pickles'
    : category === 'non-veg' ? 'Non-Veg Pickles'
    : 'All Pickles';

  return (
    <div className="container section shop">
      <div className={`shop-banner ${category || 'all'}`}>
        <h1>{title}</h1>
        <p>
          {category === 'veg' && 'శాకాహార పచ్చళ్ళు · mango, gongura, lemon, amla, chilli & more'}
          {category === 'non-veg' && 'మాంసాహార పచ్చళ్ళు · chicken, mutton, prawns, fish & crab'}
          {!category && 'Hand-made Telugu & Indian pickles, delivered fresh'}
        </p>
      </div>

      <div className="filters" role="group" aria-label="Filters">
        <div className="seg">
          {[['', 'All'], ['veg', 'Veg'], ['non-veg', 'Non-Veg']].map(([v, l]) => (
            <button key={l} className={category === v ? 'active' : ''} onClick={() => set('category', v)}>{l}</button>
          ))}
        </div>
        <select value={region} onChange={(e) => set('region', e.target.value)} aria-label="Region">
          <option value="">All regions</option>
          {regions.map((r) => <option key={r.region} value={r.region}>{r.region} ({r.count})</option>)}
        </select>
        <select value={maxSpice} onChange={(e) => set('maxSpice', e.target.value)} aria-label="Spice level">
          <option value="">Any spice level</option>
          <option value="2">Mild (≤ 2 chillies)</option>
          <option value="3">Medium (≤ 3)</option>
          <option value="4">Hot (≤ 4)</option>
        </select>
        <select value={sort} onChange={(e) => set('sort', e.target.value)} aria-label="Sort">
          {SORTS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
        {(q || region || maxSpice || bestseller) && (
          <button className="link-btn" onClick={() => setParams(category ? { category } : {})}>Clear filters</button>
        )}
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {products === null ? <Spinner /> : products.length === 0 ? (
        <div className="empty">
          <p>No pickles match these filters.</p>
        </div>
      ) : (
        <>
          <p className="muted">{products.length} pickles</p>
          <div className="grid">
            {products.map((p) => <ProductCard key={p.slug} product={p} />)}
          </div>
        </>
      )}
    </div>
  );
}
