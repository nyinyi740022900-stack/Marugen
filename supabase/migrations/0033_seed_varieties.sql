-- Seed the knowledge-base "varieties" catalog with well-known koi and
-- arowana varieties. Descriptions/traits are factual summaries of each
-- variety's standard identification points; image_url points at a
-- freely-licensed (Wikimedia Commons) reference photo. Two koi varieties
-- (Chagoi, Kumonryu) are seeded without an image because no verified
-- free-license photo of the actual fish could be sourced — an admin can
-- attach one later via the Knowledge > Varieties admin screen.
-- Only inserts rows that don't already exist (by name), so this is safe
-- to run even if some varieties were added manually beforehand.

insert into public.varieties (name, category, description, image_url, traits)
select v.name, v.category, v.description, v.image_url, v.traits
from (values
  (
    'Kohaku',
    'koi',
    'The oldest and most popular koi variety: a white (shiroji) body carrying a red (hi) pattern with no other colours. Considered the foundation of all modern nishikigoi and the benchmark for judging skin quality and pattern balance.',
    'https://upload.wikimedia.org/wikipedia/commons/4/45/KohakuLJA.jpg',
    array['Pure white base (shiroji)', 'Unbroken red (hi) pattern', 'No black or other colours', 'Pattern should not touch the eyes or lips']
  ),
  (
    'Taisho Sanke (Sanke)',
    'koi',
    'A white-bodied koi with red (hi) and black (sumi) markings, one of the "Gosanke" (big three) varieties alongside Kohaku and Showa. Black sumi typically appears only above the lateral line, never on the head as a solid patch.',
    'https://upload.wikimedia.org/wikipedia/commons/7/73/Sanke2.JPG',
    array['White base with red and black', 'Sumi (black) mainly above the lateral line', 'No black on the pectoral fins base area', 'Part of the Gosanke group']
  ),
  (
    'Showa Sanshoku (Showa)',
    'koi',
    'A black-bodied (sumi) koi overlaid with red (hi) and white (shiro) markings — the inverse balance of Sanke. Named after the Showa era of Japan when it was developed. Also part of the Gosanke.',
    'https://upload.wikimedia.org/wikipedia/commons/5/56/Showa4.JPG',
    array['Black (sumi) base colour', 'Red and white markings over black', 'Sumi often wraps around the head', 'Part of the Gosanke group']
  ),
  (
    'Shiro Utsuri',
    'koi',
    'An Utsurimono variety with a black body and bold white (shiro) markings — essentially the black/white reversal of Shiro Bekko. Known for its striking contrast and is one of the more common Utsuri varieties.',
    'https://upload.wikimedia.org/wikipedia/commons/0/0d/Shiro_Utsuri.jpg',
    array['Black base with white pattern', 'High contrast, bold markings', 'Black should extend to the head', 'Utsurimono family']
  ),
  (
    'Asagi',
    'koi',
    'One of the oldest koi varieties: pale blue-grey net-patterned (reticulated) scales on the back with red (hi) on the cheeks, fins and belly. Prized for the neatness of its net pattern rather than bold colour contrast.',
    'https://upload.wikimedia.org/wikipedia/commons/2/2a/Koi_asagi.jpg',
    array['Blue-grey net (reticulated) scale pattern on back', 'Red on cheeks, fins and belly', 'Non-metallic', 'One of the six original koi varieties']
  ),
  (
    'Shusui',
    'koi',
    'The scaleless (doitsu) sister variety of Asagi, created by crossing Asagi with German mirror carp. Has a single row of large blue-grey scales along the dorsal line instead of a full net pattern, with red along the sides.',
    'https://upload.wikimedia.org/wikipedia/commons/7/76/Shusui.JPG',
    array['Doitsu (scaleless) body', 'Single row of scales along the spine', 'Blue-grey back, red sides', 'Descended from Asagi']
  ),
  (
    'Yamabuki Ogon',
    'koi',
    'A Hikarimuji (single-colour metallic) variety: a solid, uniform metallic golden-yellow body with no pattern. One of the easiest koi varieties to keep and spot in a pond because of its bright, unbroken colour.',
    'https://upload.wikimedia.org/wikipedia/commons/d/d9/2_year_old_Yamabuki.jpg',
    array['Solid metallic gold/yellow', 'No pattern — single colour', 'Strong, even metallic lustre', 'Hikarimuji (Ogon) family']
  ),
  (
    'Kujaku',
    'koi',
    'A Hikarimoyo (metallic multi-colour) variety combining a metallic platinum base, a net-like matsuba (pinecone) scale pattern, and Kohaku-style red markings. The name means "peacock" in Japanese.',
    'https://upload.wikimedia.org/wikipedia/commons/c/c4/Kujaku2.JPG',
    array['Metallic platinum/silver base', 'Matsuba (net/pinecone) scale reticulation', 'Red (hi) pattern over the net', 'Hikarimoyo family']
  ),
  (
    'Koromo (Ai Goromo / Budo Goromo)',
    'koi',
    'A Kohaku-pattern koi where each scale within the red pattern carries a blue or purple-black edge, giving the hi a textured, layered look. "Budo Goromo" (grape-robe) refers to a deep purple, grape-cluster-like version.',
    'https://upload.wikimedia.org/wikipedia/commons/4/42/Budo_Goromo.jpg',
    array['White base with Kohaku-style red pattern', 'Blue/purple edging on scales within the red', 'Pattern deepens with age', 'Koromo family']
  ),
  (
    'Tancho',
    'koi',
    'Not a separate breeding line but a pattern designation: any otherwise white-bodied koi (Tancho Kohaku, Tancho Showa, Tancho Sanke) carrying a single, round red spot on the crown of the head, echoing the Japanese red-crowned crane.',
    'https://upload.wikimedia.org/wikipedia/commons/8/85/Tanchosanke.JPG',
    array['Single red spot on the head only', 'No red anywhere else on the body', 'Named after the tancho (red-crowned crane)', 'Very difficult to breed reliably']
  ),
  (
    'Ginrin',
    'koi',
    'A scale-type designation, not a colour variety: individual scales carry a sparkling, diamond-like metallic shine (a glittering variant of ordinary scales). Can appear on almost any koi variety, e.g. "Ginrin Kohaku".',
    'https://upload.wikimedia.org/wikipedia/commons/e/e3/Ginrin_Aragoke.jpg',
    array['Sparkling, glittery individual scales', 'Can be combined with any colour variety', 'Types include beta-gin, kado-gin and tama-gin', 'Judged by evenness of sparkle']
  ),
  (
    'Butterfly Koi (Hirenaga)',
    'koi',
    'A long-finned koi variety developed by crossing ordinary koi with Indonesian longfin carp. Any colour pattern can appear on a butterfly koi — it is the flowing, oversized fins and tail that define the type, not the colouring.',
    'https://upload.wikimedia.org/wikipedia/commons/a/a0/Butterfly_Koi.jpg',
    array['Long, flowing pectoral, dorsal and tail fins', 'Any colour/pattern possible', 'Not a traditional (Gosanke show) variety', 'Also called Hirenaga or dragon carp']
  ),
  (
    'Chagoi',
    'koi',
    'A solid, unpatterned tea-brown to copper-coloured koi with a non-metallic finish. Famous among hobbyists for being the fastest-growing, largest and by far the friendliest, most hand-tame koi variety.',
    null,
    array['Solid tea-brown/copper colour, no pattern', 'Non-metallic', 'Among the fastest-growing and largest koi', 'Known for a friendly, hand-tame temperament']
  ),
  (
    'Kumonryu',
    'koi',
    'A doitsu (scaleless) black-and-white koi whose ink-black markings can shift and change over time with water temperature and season, evoking the "nine-crested dragon" the name refers to. Bred from Shusui and black doitsu koi.',
    null,
    array['Doitsu (scaleless) body', 'Black pattern on white, shifts over time', 'No red — pattern changes with temperature/season', 'Name means "nine-crested dragon"']
  ),
  (
    'Super Red Arowana',
    'arowana',
    'A colour form of the Asian arowana (Scleropages legendrei) native to the upper Kapuas River basin in West Kalimantan, Indonesia. Juveniles show pale pink-red fin edges that intensify with age and diet into a deep blood-red across the body, fins and scale edges.',
    'https://upload.wikimedia.org/wikipedia/commons/9/9c/Red_Arowana034.JPG',
    array['Deepening red colour with age/diet', 'Native to the Kapuas basin, Kalimantan', 'Scleropages legendrei', 'CITES Appendix I — captive-bred stock only']
  ),
  (
    'Golden Crossback Arowana',
    'arowana',
    'A colour form of the Asian arowana (Scleropages formosus) from Bukit Merah, Malaysia, prized for gold colouration that extends up past the fourth scale row onto the back ("crossing the back"), unlike the lower Golden Red-Tail form.',
    'https://upload.wikimedia.org/wikipedia/commons/f/f6/Gold_Arowana035.JPG',
    array['Gold colour extends onto the back scale rows', 'Base scale colour blue, purple or gold', 'Native to Bukit Merah, Malaysia', 'Scleropages formosus — CITES Appendix I']
  ),
  (
    'Silver Arowana',
    'arowana',
    'Osteoglossum bicirrhosum, native to the Amazon basin. The most affordable and widely kept arowana, with a streamlined silver body, large upturned mouth and long barbels used to detect surface prey. Not CITES-restricted.',
    'https://upload.wikimedia.org/wikipedia/commons/5/56/Arowana%28Osteoglossum_bicirrhosum%29.jpg',
    array['Elongated silver body', 'Large upturned mouth with two barbels', 'Native to the Amazon basin', 'Osteoglossum bicirrhosum']
  ),
  (
    'Jardini (Australian/Pearl) Arowana',
    'arowana',
    'Scleropages jardinii, native to northern Australia and southern New Guinea. Each scale carries a reticulated, pearl-like pattern with reddish to green-gold flecking, giving it a mottled "spotted" look distinct from the Asian arowana varieties.',
    'https://upload.wikimedia.org/wikipedia/commons/1/1c/Scleropages_jardinii_043.JPG',
    array['Reticulated, pearl-flecked scale pattern', 'Reddish to green-gold scale edges', 'Native to northern Australia and New Guinea', 'Scleropages jardinii — not CITES-restricted']
  )
) as v(name, category, description, image_url, traits)
where not exists (
  select 1 from public.varieties existing where existing.name = v.name
);
