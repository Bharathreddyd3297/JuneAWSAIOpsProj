// Hand-drawn SVG pickle jar. Every product gets its own jar coloured by its pickle,
// a cloth "moota" cover (green = veg, red = non-veg) and a label. No image files needed.
function seeded(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 16777619);
  return () => {
    h = Math.imul(h ^ (h >>> 15), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return ((h ^= h >>> 16) >>> 0) / 4294967296;
  };
}

function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const c = (v) => Math.max(0, Math.min(255, v + amt));
  return `#${[(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => c(v).toString(16).padStart(2, '0')).join('')}`;
}

export default function PickleJar({ product, size = 160, showLabel = true }) {
  const { slug = 'jar', color = '#B5381F', category = 'veg', name = '', localName = '' } = product || {};
  const rnd = seeded(slug);
  const cloth = category === 'veg' ? '#2E7D32' : '#C62828';
  const clothDark = category === 'veg' ? '#1B5E20' : '#8E1414';
  const id = `j-${slug}`;
  const bits = Array.from({ length: 34 }, () => ({
    x: 30 + rnd() * 100,
    y: 82 + rnd() * 92,
    r: 1.2 + rnd() * 3.2,
    light: rnd() > 0.55,
  }));
  const label = name.replace(/ Pickle| Pachadi| Ooragaya| Achaar| Achar/gi, '').trim();
  const longLabel = label.length > 11;

  return (
    <svg viewBox="0 0 160 200" width={size} height={size * 1.25} role="img" aria-label={`${name} jar`} className="jar">
      <defs>
        <linearGradient id={`${id}-glass`} x1="0" x2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.55" />
          <stop offset="0.18" stopColor="#fff" stopOpacity="0.08" />
          <stop offset="0.8" stopColor="#000" stopOpacity="0.04" />
          <stop offset="1" stopColor="#000" stopOpacity="0.18" />
        </linearGradient>
        <linearGradient id={`${id}-fill`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={shade(color, 28)} />
          <stop offset="1" stopColor={shade(color, -30)} />
        </linearGradient>
        <clipPath id={`${id}-clip`}>
          <rect x="22" y="58" width="116" height="128" rx="26" />
        </clipPath>
        <pattern id={`${id}-dots`} width="10" height="10" patternUnits="userSpaceOnUse">
          <circle cx="5" cy="5" r="1.6" fill="#FFF3D6" opacity="0.8" />
        </pattern>
      </defs>

      <ellipse cx="80" cy="190" rx="58" ry="6" fill="#000" opacity="0.12" />

      {/* jar body (glass) */}
      <rect x="22" y="58" width="116" height="128" rx="26" fill="#FFFDF8" stroke="#D9CBB8" strokeWidth="2" />
      {/* pickle contents */}
      <g clipPath={`url(#${id}-clip)`}>
        <rect x="22" y="76" width="116" height="112" fill={`url(#${id}-fill)`} />
        <rect x="22" y="72" width="116" height="8" fill="#E8B23A" opacity="0.55" />
        {bits.map((b, i) => (
          <circle key={i} cx={b.x} cy={b.y} r={b.r} fill={b.light ? shade(color, 60) : shade(color, -55)} opacity="0.75" />
        ))}
      </g>
      <rect x="22" y="58" width="116" height="128" rx="26" fill={`url(#${id}-glass)`} />
      <rect x="32" y="70" width="8" height="96" rx="4" fill="#fff" opacity="0.35" />

      {/* neck */}
      <rect x="38" y="42" width="84" height="20" rx="6" fill="#FFFDF8" stroke="#D9CBB8" strokeWidth="2" />

      {/* cloth cover tied over the lid */}
      <path
        d="M30 44 C30 22, 130 22, 130 44 L136 58 Q128 64 120 58 Q112 66 104 58 Q96 66 88 58 Q80 66 72 58 Q64 66 56 58 Q48 66 40 58 Q32 64 24 58 Z"
        fill={cloth}
      />
      <path
        d="M30 44 C30 22, 130 22, 130 44 L136 58 Q128 64 120 58 Q112 66 104 58 Q96 66 88 58 Q80 66 72 58 Q64 66 56 58 Q48 66 40 58 Q32 64 24 58 Z"
        fill={`url(#${id}-dots)`}
      />
      <path d="M32 48 Q80 56 128 48" stroke="#E0A526" strokeWidth="3" fill="none" />
      <circle cx="128" cy="49" r="3.2" fill="#E0A526" />
      <path d="M128 50 q4 8 0 14 M128 50 q-2 9 -6 13" stroke="#E0A526" strokeWidth="2" fill="none" />
      <path d="M44 30 Q80 20 116 30" stroke={clothDark} strokeWidth="2" fill="none" opacity="0.5" />

      {/* label */}
      {showLabel && (
        <g>
          <rect x="36" y="104" width="88" height="50" rx="8" fill="#FFF9F0" stroke={cloth} strokeWidth="2.5" />
          <rect x="40" y="108" width="80" height="42" rx="5" fill="none" stroke={cloth} strokeWidth="0.8" strokeDasharray="3 2" />
          <text
            x="80" y="127" textAnchor="middle" fontFamily="Yeseva One, Georgia, serif" fontSize="12.5" fill="#3A1D10"
            {...(longLabel ? { textLength: 72, lengthAdjust: 'spacingAndGlyphs' } : {})}
          >
            {label}
          </text>
          <text
            x="80" y="143" textAnchor="middle" fontFamily="Noto Sans Telugu, sans-serif" fontSize="9" fill={clothDark}
            {...(localName.length > 14 ? { textLength: 74, lengthAdjust: 'spacingAndGlyphs' } : {})}
          >
            {localName}
          </text>
        </g>
      )}
    </svg>
  );
}
