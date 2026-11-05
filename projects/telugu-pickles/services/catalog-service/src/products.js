// Seed catalogue: traditional Telugu (Andhra / Telangana / Rayalaseema) pickles
// plus a few beloved pickles from across India.
// price500g is in INR. color = colour of the pickle used by the SVG jar artwork.
const veg = [
  {
    slug: 'avakaya', name: 'Avakaya', localName: 'ఆవకాయ', region: 'Coastal Andhra', spice: 4, price500g: 349, bestseller: true, color: '#B5381F',
    description: 'The king of Telugu pickles. Hand-cut raw Banginapalli mango with the seed shell, mustard powder, Guntur chilli and cold-pressed groundnut oil. Matured in ceramic jaadis for 21 days.',
    ingredients: 'Raw mango, Guntur red chilli powder, mustard powder, salt, groundnut oil, fenugreek, garlic',
  },
  {
    slug: 'bellam-avakaya', name: 'Bellam Avakaya', localName: 'బెల్లం ఆవకాయ', region: 'Godavari', spice: 2, price500g: 379, color: '#9C4A1A',
    description: 'Sweet-and-spicy mango pickle made with pure jaggery. The Godavari favourite that kids and grandparents both love.',
    ingredients: 'Raw mango, jaggery, red chilli powder, mustard, salt, groundnut oil',
  },
  {
    slug: 'magaya', name: 'Magaya', localName: 'మాగాయ', region: 'Coastal Andhra', spice: 3, price500g: 369, color: '#C0602A',
    description: 'Thin mango slices sun-dried on terraces, then soaked in a tangy chilli-mustard masala. Perfect with curd rice.',
    ingredients: 'Sun-dried mango, red chilli powder, mustard, fenugreek, salt, sesame oil',
  },
  {
    slug: 'gongura', name: 'Gongura Pachadi', localName: 'గోంగూర పచ్చడి', region: 'Telangana', spice: 4, price500g: 299, bestseller: true, color: '#4E5A23',
    description: 'Sorrel (red-stem gongura) leaves roasted and ground with red chillies and garlic. The pride of Andhra & Telangana.',
    ingredients: 'Gongura leaves, red chilli, garlic, mustard, cumin, salt, groundnut oil',
  },
  {
    slug: 'tomato-pachadi', name: 'Tomato Pachadi', localName: 'టమాటో పచ్చడి', region: 'Rayalaseema', spice: 3, price500g: 279, color: '#B22A1E',
    description: 'Country tomatoes slow-cooked with tamarind and tempered with mustard and curry leaves. Rayalaseema style.',
    ingredients: 'Tomato, tamarind, red chilli, garlic, mustard, curry leaves, salt, oil',
  },
  {
    slug: 'nimmakaya', name: 'Nimmakaya Ooragaya', localName: 'నిమ్మకాయ ఊరగాయ', region: 'Coastal Andhra', spice: 3, price500g: 259, color: '#C9A227',
    description: 'Juicy country lemons cured in salt and turmeric for weeks, then spiced. Gets better with every month.',
    ingredients: 'Lemon, salt, turmeric, red chilli, fenugreek, mustard, oil',
  },
  {
    slug: 'usirikaya', name: 'Usirikaya Pachadi', localName: 'ఉసిరికాయ పచ్చడి', region: 'Telangana', spice: 3, price500g: 319, color: '#7A8B2E',
    description: 'Indian gooseberry (amla) pickle, packed with vitamin C. Tangy, spicy and a winter-time staple.',
    ingredients: 'Amla, red chilli, mustard, fenugreek, garlic, salt, groundnut oil',
  },
  {
    slug: 'allam', name: 'Allam Pachadi', localName: 'అల్లం పచ్చడి', region: 'Coastal Andhra', spice: 3, price500g: 299, color: '#8A5A2B',
    description: 'Fresh ginger with tamarind and jaggery. The classic accompaniment to pesarattu and idli.',
    ingredients: 'Ginger, tamarind, jaggery, red chilli, urad dal, mustard, salt, oil',
  },
  {
    slug: 'vellulli', name: 'Vellulli Ooragaya', localName: 'వెల్లుల్లి ఊరగాయ', region: 'Telangana', spice: 4, price500g: 339, color: '#A64B2A',
    description: 'Whole peeled garlic pods in a fiery red chilli masala. A must-have for garlic lovers.',
    ingredients: 'Garlic, red chilli powder, tamarind, mustard, fenugreek, salt, oil',
  },
  {
    slug: 'pandu-mirapakaya', name: 'Pandu Mirapakaya', localName: 'పండు మిరపకాయ పచ్చడి', region: 'Guntur', spice: 5, price500g: 299, bestseller: true, color: '#9E1B12',
    description: 'Ripe red Guntur chillies ground with tamarind and garlic. Only for the brave. Our spiciest veg pickle.',
    ingredients: 'Ripe red chilli, tamarind, garlic, mustard, fenugreek, salt, oil',
  },
  {
    slug: 'pachi-mirapakaya', name: 'Pachi Mirapakaya', localName: 'పచ్చి మిరపకాయ ఊరగాయ', region: 'Guntur', spice: 5, price500g: 279, color: '#3E6B26',
    description: 'Slit green chillies stuffed with mustard and lemon. Sharp, crunchy and very hot.',
    ingredients: 'Green chilli, mustard, lemon juice, fenugreek, salt, oil',
  },
  {
    slug: 'dosavakaya', name: 'Dosavakaya', localName: 'దోసావకాయ', region: 'Godavari', spice: 3, price500g: 289, color: '#C77B22',
    description: 'Yellow cucumber (dosakaya) cubes in mustard masala. Made fresh, light and crunchy.',
    ingredients: 'Yellow cucumber, mustard powder, red chilli, salt, groundnut oil',
  },
  {
    slug: 'chintakaya', name: 'Chintakaya Pachadi', localName: 'చింతకాయ పచ్చడి', region: 'Telangana', spice: 4, price500g: 329, color: '#5A3A1E',
    description: 'Raw tender tamarind pounded with green chillies the traditional rolu way. Sour, spicy, unforgettable.',
    ingredients: 'Raw tamarind, green chilli, red chilli, mustard, fenugreek, salt, oil',
  },
  {
    slug: 'kakarakaya', name: 'Kakarakaya Pachadi', localName: 'కాకరకాయ పచ్చడి', region: 'Coastal Andhra', spice: 3, price500g: 309, color: '#3F5E2A',
    description: 'Crispy fried bitter gourd balanced with tamarind and jaggery. Even bitter-gourd haters ask for more.',
    ingredients: 'Bitter gourd, tamarind, jaggery, red chilli, mustard, salt, oil',
  },
  {
    slug: 'cauliflower', name: 'Cauliflower Ooragaya', localName: 'కాలీఫ్లవర్ ఊరగాయ', region: 'Telangana', spice: 3, price500g: 289, color: '#C08A3A',
    description: 'Crunchy cauliflower florets in mustard-chilli masala. A Hyderabadi winter favourite.',
    ingredients: 'Cauliflower, mustard, red chilli, lemon, salt, oil',
  },
  {
    slug: 'mixed-veg', name: 'Mixed Vegetable Pickle', localName: 'మిక్స్డ్ వెజ్ ఊరగాయ', region: 'Coastal Andhra', spice: 3, price500g: 299, color: '#B5502A',
    description: 'Carrot, beans, mango, lemon and green chilli together in one jar. A little of everything.',
    ingredients: 'Carrot, beans, mango, lemon, green chilli, mustard, red chilli, salt, oil',
  },
  {
    slug: 'aam-ka-achaar', name: 'Punjabi Aam ka Achaar', localName: 'आम का अचार', region: 'Punjab', spice: 3, price500g: 329, color: '#B8742A',
    description: 'North-Indian style mango pickle with fennel, nigella and mustard oil.',
    ingredients: 'Raw mango, mustard oil, fennel, nigella, fenugreek, red chilli, turmeric, salt',
  },
  {
    slug: 'gujarati-chundo', name: 'Gujarati Chundo', localName: 'છુંદો', region: 'Gujarat', spice: 1, price500g: 339, color: '#D8902E',
    description: 'Grated mango slow-cooked in sugar syrup with a hint of chilli and cumin. Sweet, mild and jammy.',
    ingredients: 'Raw mango, sugar, red chilli, cumin, salt',
  },
  {
    slug: 'kerala-naranga', name: 'Kerala Naranga Achar', localName: 'നാരങ്ങ അച്ചാർ', region: 'Kerala', spice: 3, price500g: 279, color: '#A7651F',
    description: 'Lime pickle tempered in gingelly oil with Kashmiri chilli and asafoetida, Kerala sadhya style.',
    ingredients: 'Lime, Kashmiri chilli, gingelly oil, asafoetida, fenugreek, mustard, salt',
  },
  {
    slug: 'ker-sangri', name: 'Rajasthani Ker Sangri', localName: 'केर सांगरी', region: 'Rajasthan', spice: 3, price500g: 449, color: '#6B4A2B',
    description: 'Desert berries (ker) and beans (sangri) from the Thar, pickled in mustard oil with dry mango.',
    ingredients: 'Ker berries, sangri beans, mustard oil, amchur, red chilli, fennel, salt',
  },
];

const nonVeg = [
  {
    slug: 'kodi-boneless', name: 'Boneless Chicken Pickle', localName: 'బోన్‌లెస్ కోడి పచ్చడి', region: 'Coastal Andhra', spice: 4, price500g: 649, bestseller: true, color: '#8E2A14',
    description: 'Tender boneless chicken fried crisp and folded into our house red-chilli masala with lots of garlic.',
    ingredients: 'Chicken, red chilli powder, garlic, ginger, garam masala, lemon, salt, groundnut oil',
  },
  {
    slug: 'kodi-bone', name: 'Chicken Pickle (Bone-in)', localName: 'కోడి పచ్చడి', region: 'Coastal Andhra', spice: 4, price500g: 549, color: '#9A3418',
    description: 'Classic bone-in chicken pickle, the way it is made for Sankranti in Andhra homes.',
    ingredients: 'Chicken, red chilli, garlic, ginger, spices, lemon, salt, oil',
  },
  {
    slug: 'natu-kodi', name: 'Natu Kodi Pickle', localName: 'నాటు కోడి పచ్చడి', region: 'Telangana', spice: 5, price500g: 799, color: '#7A2210',
    description: 'Country chicken, slow-fried for deep flavour. Fiery Telangana style.',
    ingredients: 'Country chicken, red chilli, garlic, ginger, cloves, cinnamon, lemon, salt, oil',
  },
  {
    slug: 'gongura-chicken', name: 'Gongura Chicken Pickle', localName: 'గోంగూర చికెన్ పచ్చడి', region: 'Coastal Andhra', spice: 4, price500g: 699, bestseller: true, color: '#5A3A1A',
    description: 'Boneless chicken meets tangy gongura leaves. The most-loved combination in Andhra.',
    ingredients: 'Chicken, gongura leaves, red chilli, garlic, spices, salt, oil',
  },
  {
    slug: 'mamsam', name: 'Mutton Pickle', localName: 'మటన్ పచ్చడి', region: 'Telangana', spice: 4, price500g: 899, bestseller: true, color: '#6E1E12',
    description: 'Boneless goat meat pieces slow-cooked and fried, then pickled with spices. Rich and meaty.',
    ingredients: 'Mutton, red chilli, garlic, ginger, garam masala, lemon, salt, oil',
  },
  {
    slug: 'gongura-mutton', name: 'Gongura Mutton Pickle', localName: 'గోంగూర మటన్ పచ్చడి', region: 'Telangana', spice: 5, price500g: 949, color: '#4E3418',
    description: 'Mutton and gongura, the legendary Telangana pairing, in a jar.',
    ingredients: 'Mutton, gongura leaves, red chilli, garlic, spices, salt, oil',
  },
  {
    slug: 'mutton-kheema', name: 'Mutton Kheema Pickle', localName: 'మటన్ కీమా పచ్చడి', region: 'Hyderabad', spice: 4, price500g: 949, color: '#7B2A16',
    description: 'Minced mutton roasted with Hyderabadi spices. Spread it on hot rice with ghee.',
    ingredients: 'Minced mutton, red chilli, ginger-garlic, garam masala, lemon, salt, oil',
  },
  {
    slug: 'royyala', name: 'Prawn Pickle', localName: 'రొయ్యల పచ్చడి', region: 'Godavari', spice: 4, price500g: 899, bestseller: true, color: '#B0451E',
    description: 'Fresh Godavari prawns, cleaned, fried and pickled in garlic-chilli masala.',
    ingredients: 'Prawns, red chilli, garlic, ginger, lemon, spices, salt, oil',
  },
  {
    slug: 'gongura-royyalu', name: 'Gongura Prawns Pickle', localName: 'గోంగూర రొయ్యల పచ్చడి', region: 'Godavari', spice: 4, price500g: 949, color: '#6A4A1E',
    description: 'Prawns tossed with roasted gongura. Tangy, spicy and coastal.',
    ingredients: 'Prawns, gongura leaves, red chilli, garlic, spices, salt, oil',
  },
  {
    slug: 'endu-royyalu', name: 'Dry Prawn Pickle', localName: 'ఎండు రొయ్యల పచ్చడి', region: 'Nellore', spice: 4, price500g: 749, color: '#A0521E',
    description: 'Sun-dried prawns (endu royyalu) from Nellore, roasted and pickled. Intense and crunchy.',
    ingredients: 'Dried prawns, red chilli, garlic, tamarind, spices, salt, oil',
  },
  {
    slug: 'chepala', name: 'Fish Pickle (Korameenu)', localName: 'చేపల పచ్చడి', region: 'Godavari', spice: 4, price500g: 799, color: '#93401C',
    description: 'Boneless murrel (korameenu) fish cubes, fried and pickled the Godavari way.',
    ingredients: 'Murrel fish, red chilli, garlic, ginger, lemon, spices, salt, oil',
  },
  {
    slug: 'peethala', name: 'Crab Pickle', localName: 'పీతల పచ్చడి', region: 'Coastal Andhra', spice: 4, price500g: 999, color: '#A23A18',
    description: 'Mud crab meat roasted with coastal spices. A rare delicacy from Bhimavaram.',
    ingredients: 'Crab meat, red chilli, garlic, ginger, spices, lemon, salt, oil',
  },
  {
    slug: 'kodi-guddu', name: 'Egg Pickle', localName: 'కోడి గుడ్డు పచ్చడి', region: 'Telangana', spice: 3, price500g: 449, color: '#C27A2C',
    description: 'Boiled eggs, shallow-fried and pickled in a tangy chilli masala.',
    ingredients: 'Eggs, red chilli, garlic, tamarind, spices, salt, oil',
  },
  {
    slug: 'goan-prawn-balchao', name: 'Goan Prawn Balchão', localName: 'Balchão', region: 'Goa', spice: 4, price500g: 899, color: '#A8321A',
    description: 'Goan prawn pickle in a sweet-sour-spicy toddy vinegar masala.',
    ingredients: 'Prawns, Kashmiri chilli, vinegar, garlic, sugar, spices, salt, oil',
  },
  {
    slug: 'kerala-meen-achar', name: 'Kerala Meen Achar', localName: 'മീൻ അച്ചാർ', region: 'Kerala', spice: 4, price500g: 799, color: '#8C3A1C',
    description: 'Seer fish pickle with Kashmiri chilli, ginger and coconut vinegar.',
    ingredients: 'Seer fish, Kashmiri chilli, ginger, garlic, vinegar, gingelly oil, salt',
  },
  {
    slug: 'coorg-pandi', name: 'Coorg Pandi Pickle', localName: 'Pandi Achar', region: 'Coorg', spice: 4, price500g: 849, color: '#6A2A18',
    description: 'Kodava-style pork pickle with kachampuli (black vinegar) and black pepper.',
    ingredients: 'Pork, kachampuli vinegar, black pepper, red chilli, garlic, salt, oil',
  },
];

// Deterministic "ratings" so the demo looks realistic and stable.
function enrich(p, i, category) {
  return {
    ...p,
    category,
    bestseller: !!p.bestseller,
    rating: Number((4.2 + ((i * 7) % 8) / 10).toFixed(1)),
    reviews: 40 + ((i * 37) % 460),
    shelfLifeDays: category === 'veg' ? 365 : 90,
    stockGrams: 50000,
  };
}

module.exports = [
  ...veg.map((p, i) => enrich(p, i, 'veg')),
  ...nonVeg.map((p, i) => enrich(p, i + 3, 'non-veg')),
];
