-- Round 2 of Care Guides: general koi/arowana husbandry plus guides
-- specific to keeping fish in Singapore (PUB's chloraminated tap water,
-- the tropical climate, and the legal requirements around Asian arowana).
--
-- Facts checked before writing:
-- • PUB (Singapore's water agency) switched from chlorine to chloramine
--   disinfection in 2003; chloramine does not off-gas from standing water
--   the way plain chlorine does.
-- • Asian arowana (Scleropages formosus — Super Red, Golden Crossback,
--   etc.) is CITES Appendix I listed. Keeping/selling one in Singapore
--   legally requires it to be captive-bred, microchipped, and registered
--   with NParks' Animal & Veterinary Service (AVS) with a valid CITES
--   certificate; AVS's eservices portal has a dedicated "CITES Dragonfish
--   (arowana) Registration" service for this.
--
-- body_markdown is rendered as plain Text (see knowledge_screen.dart), so
-- it uses "•" bullets and plain paragraphs rather than markdown syntax.
--
-- No cover_image_url is set on any of these for the same reason as the
-- first care-guides migration: no genuine, correctly identified
-- free-license photo was sourced for these topics, and a wrong image
-- would be worse than none.
--
-- Only inserts rows that don't already exist (by title).

insert into public.knowledge_articles (title, body_markdown, published_at)
select v.title, v.body_markdown, v.published_at
from (values
  (
    'Keeping Arowana Legally in Singapore',
    $body$Asian arowana — the variety Marugen sells as Super Red and Golden Crossback — is listed under CITES Appendix I, the strictest international protection category. Keeping one in Singapore is legal, but only under specific conditions, and this is a real legal requirement, not a formality.

WHAT'S REQUIRED
• The fish must be captive-bred (wild-caught Asian arowana cannot be traded).
• It must be individually microchipped by the breeder/exporter before export.
• It must be registered with NParks' Animal & Veterinary Service (AVS) — AVS's eservices portal has a dedicated "CITES Dragonfish (Arowana) Registration" service for this.
• A valid CITES certificate must travel with the fish from breeder to import to final owner.

WHY THIS MATTERS TO YOU AS A BUYER
An arowana without a microchip and matching CITES paperwork cannot be legally owned in Singapore, no matter how healthy or well-priced it looks. Always ask to see the microchip certificate and confirm the chip number matches the fish (a vet or the seller can scan it) before you buy — this protects you from an import that was never properly declared.

WHAT MARUGEN PROVIDES
Every arowana sold by Marugen is captive-bred, microchipped, and comes with its CITES documentation, so ownership transfer can be completed through AVS in your name.

This guide is general information, not legal advice — for the current official process, check NParks AVS's own eservices portal.$body$,
    now() - interval '5 days'
  ),
  (
    'Singapore Tap Water: Why PUB Water Needs a Conditioner Every Time',
    $body$Singapore's tap water, supplied by PUB, has used chloramine as its disinfectant since 2003 — not plain chlorine. This one fact changes how you should treat water for a koi or arowana pond.

THE KEY DIFFERENCE
Plain chlorine mostly off-gasses out of water left standing uncovered for 24–48 hours. Chloramine does not — it's chlorine chemically bonded to ammonia, and that bond holds for days even in an open container. "Just letting a pail of tap water sit overnight" — a tip that works in some countries — is not reliable for PUB water and can still leave enough active chloramine to stress or injure your fish's gills.

WHAT THIS MEANS PRACTICALLY
• Every top-up, not just full water changes, needs a dechlorinator — a small daily top-up of untreated PUB water adds up to real gill irritation over time.
• Use a conditioner that specifically states it breaks the chlorine–ammonia bond (removes chloramine), not just "removes chlorine" — a chlorine-only product can leave the ammonia behind, which then shows up as an ammonia spike on your test kit.
• PUB water is also relatively soft (low general/carbonate hardness), so if you're topping up a lot during Singapore's dry spells, keep an eye on pH stability as well as chlorine/chloramine.

See the "Anti-Chlorine / Dechlorinator" guide for dosing details — the short version for Singapore is: treat every addition of tap water, every time, with a chloramine-rated conditioner.$body$,
    now() - interval '4 days'
  ),
  (
    'Managing Your Pond in Singapore''s Tropical Climate',
    $body$Singapore's year-round warm weather is actually an advantage for koi and arowana — there's no winter slowdown, and fish feed and grow steadily all year. But the same heat and heavy rainfall bring their own risks that temperate-climate care guides don't cover.

HEAT & OXYGEN
Warmer water holds less dissolved oxygen than cool water, and fish metabolism — and their oxygen demand — rises with temperature too. A pond that copes fine most of the year can get dangerously low on oxygen during a hot, still, sunny afternoon. Keep aeration (air stones, waterfalls, fountains) running especially hard during the hottest parts of the day, and consider shading part of the pond so fish have a cooler zone to retreat to.

DIRECT SUN & ALGAE
Singapore's strong equatorial sun drives fast algae growth in an exposed pond. Partial shade (a pergola, floating plants, or pond-side trees) reduces both overheating and green-water algae blooms — this pairs well with a UV sterilizer (see that guide) rather than replacing it.

SUDDEN HEAVY RAIN
Afternoon thunderstorms can dump a large volume of water into an open pond very quickly, diluting pond chemistry and shifting pH within a short time, and risking an overflow that washes fish out if the pond has no overflow drain. Make sure your pond has a proper overflow outlet above the normal waterline, and check pH after any unusually heavy storm.

NO NEED FOR HEATERS
Unlike temperate-climate koi keeping, Singapore ponds essentially never need a heater — the risk here runs the other way (overheating), not cold stress.$body$,
    now() - interval '3 days'
  ),
  (
    'Feeding Koi & Arowana: Getting the Basics Right',
    $body$Overfeeding is the single most common mistake in both koi ponds and arowana tanks — it fouls the water faster than any filter can keep up with, and drives the ammonia spikes that stress fish.

KOI
• Feed only what fish finish within 3–5 minutes, 2–3 times a day.
• Use a food matched to the season/size: higher-protein growth food for young/growing koi, a balanced maintenance food for adults.
• In Singapore's warm water, koi digest food quickly year-round, so a consistent daily feeding schedule works — there's no need to cut back for a "winter" the way temperate-climate keepers do.
• Skip a feeding (don't force it) if the water looks cloudy or fish seem lethargic — that's often an early water-quality sign, not an appetite problem.

AROWANA
• Arowana are primarily carnivorous predators — live or frozen feeder food (crickets, prawns, small fish) rather than flake food.
• Feed juveniles more frequently (small amounts, several times a day); adults do well on one larger feeding a day, several times a week.
• Only feed what's eaten within a few minutes — uneaten live feed still fouls the water, and uneaten dead feed fouls it faster.
• Avoid feeder fish/insects from unknown sources — they can introduce parasites or disease into your tank.

GENERAL RULE
When unsure, underfeed rather than overfeed — a missed meal is far less risky to your fish than a water-quality crash from excess food breaking down.$body$,
    now() - interval '2 days'
  ),
  (
    'Quarantining New Fish Before Adding Them to Your Pond',
    $body$A new koi or arowana can look perfectly healthy and still be carrying a parasite or disease that only shows once it's stressed — and your existing, established fish are exactly what gets exposed if you skip quarantine.

WHY IT MATTERS MORE IN SINGAPORE
Singapore's consistently warm water speeds up the life cycle of common parasites (like the ich parasite, Ichthyophthirius multifiliis) compared to cooler climates — an infection can go from unnoticeable to a visible outbreak faster here, which makes catching it in a quarantine tank before it reaches your main pond even more valuable.

HOW TO QUARANTINE
• Use a separate, bare-bottom tank or tub with its own filter and airstone — never the main pond.
• Quarantine period: 2–4 weeks minimum, longer if you notice anything unusual.
• Watch daily for: clamped fins, flashing/scratching against surfaces, white spots, cloudy eyes, unusual breathing, loss of appetite, or visible sores.
• Keep quarantine equipment (nets, buckets) separate from what you use on the main pond, or disinfect between uses — parasites and bacteria travel on wet equipment too.
• Match water parameters (temperature especially) between the quarantine tank and the main pond before the eventual transfer, to avoid shocking the fish.

Only move a fish to the main pond after the full quarantine period with no signs of illness.$body$,
    now() - interval '1 day'
  ),
  (
    'Recognising Common Koi & Arowana Health Problems Early',
    $body$Catching a health problem in its first day or two makes it far easier to treat than waiting until it's obvious — by the time symptoms are severe, the fish is already under serious stress.

SIGNS TO WATCH FOR (ANY SPECIES)
• Clamped fins (held close to the body instead of flared)
• Flashing — scratching or rubbing against pond walls/decorations
• Loss of appetite or ignoring food it normally eats eagerly
• Gasping at the surface or hanging near an air stone/waterfall
• Unusual dark or pale patches, cloudy eyes, or visible sores/ulcers
• Lethargy, hiding, or separating from other fish

COMMON ISSUES
• White spot (Ich) — tiny white grains across the body and fins; spreads fast in warm water. Common treatment involves raised temperature (where safe for the species) plus aquarium salt or a vet-recommended medication.
• Fin/tail rot — fins look ragged, frayed, or reddened at the edges; usually linked to poor water quality — fix the underlying water first, medicate second.
• Ulcers/red sores — open red patches on the body, often bacterial and frequently follows an injury or prolonged stress; needs prompt attention, sometimes a vet visit.
• Swollen body / raised scales (dropsy-like signs) — a serious internal sign; isolate the fish and seek advice quickly.

WHEN TO ACT
Water quality is the root cause of most disease outbreaks — test ammonia, nitrite and pH before assuming you need medication. If a sick fish doesn't visibly improve within a few days of water correction, or if several fish show symptoms at once, get advice from an aquatic vet or an experienced koi/arowana keeper rather than guessing with treatments.$body$,
    now()
  )
) as v(title, body_markdown, published_at)
where not exists (
  select 1 from public.knowledge_articles existing where existing.title = v.title
);
