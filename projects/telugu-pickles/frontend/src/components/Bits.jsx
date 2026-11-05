// Small presentational pieces shared across pages.

// FSSAI-style diet mark: green square + dot = veg, red/brown square + triangle = non-veg
export function DietMark({ category, size = 16 }) {
  const veg = category === 'veg';
  return (
    <span className="diet-mark" title={veg ? 'Vegetarian' : 'Non-vegetarian'} aria-label={veg ? 'Vegetarian' : 'Non-vegetarian'}>
      <svg width={size} height={size} viewBox="0 0 16 16">
        <rect x="1" y="1" width="14" height="14" rx="2" fill="#fff" stroke={veg ? '#2E7D32' : '#A52A1A'} strokeWidth="1.6" />
        {veg ? <circle cx="8" cy="8" r="3.6" fill="#2E7D32" /> : <path d="M8 4 L12 11.5 H4 Z" fill="#A52A1A" />}
      </svg>
    </span>
  );
}

export function SpiceMeter({ level }) {
  return (
    <span className="spice" title={`Spice level ${level}/5`} aria-label={`Spice level ${level} of 5`}>
      {Array.from({ length: 5 }, (_, i) => (
        <svg key={i} width="13" height="13" viewBox="0 0 24 24" className={i < level ? 'chilli on' : 'chilli'}>
          <path d="M14 3c0 2 1 3 3 3-1 1-1 2-1 3 0 7-6 12-13 12 4-3 7-8 7-13 0-2 1-3 3-3 0-1 0-2 1-2z" />
        </svg>
      ))}
    </span>
  );
}

export function Stars({ rating, reviews }) {
  return (
    <span className="stars" aria-label={`Rated ${rating} out of 5`}>
      <span className="star-icon">★</span> {rating.toFixed(1)}
      {reviews !== undefined && <span className="muted"> ({reviews})</span>}
    </span>
  );
}

export function Spinner({ label = 'Loading…' }) {
  return (
    <div className="spinner-wrap" role="status">
      <div className="spinner" />
      <span>{label}</span>
    </div>
  );
}

export function QtyStepper({ value, onChange, min = 1, max = 10, disabled }) {
  return (
    <div className="qty">
      <button type="button" aria-label="Decrease" disabled={disabled || value <= min} onClick={() => onChange(value - 1)}>−</button>
      <span>{value}</span>
      <button type="button" aria-label="Increase" disabled={disabled || value >= max} onClick={() => onChange(value + 1)}>+</button>
    </div>
  );
}
