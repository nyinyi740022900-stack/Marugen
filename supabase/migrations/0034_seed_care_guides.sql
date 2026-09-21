-- Seed the Knowledge > Care Guides section with three equipment/water-care
-- articles: Uni-Light nitrifying bacteria (matches the "Uni-Light" product
-- already sold in the shop, SKU UNILIGHT-500ML), UV sterilizers ("UV
-- light"), and anti-chlorine dechlorinators (matches the "PetFran Multi
-- Coat Anti Chlorine Solution" product already sold in the shop).
--
-- body_markdown is rendered as plain Text (no markdown renderer wired up
-- yet — see lib/features/knowledge/presentation/knowledge_screen.dart), so
-- it's written as clean plain text with "•" bullets rather than markdown
-- syntax.
--
-- No cover_image_url is set for any of these: a genuine, correctly
-- identified free-license photo of pond UV sterilizer hardware or the
-- specific dechlorinator/bacteria bottles could not be sourced from
-- Wikimedia Commons, and a wrong or stock-photo image would be worse than
-- none — an admin can attach real product/equipment photos later via the
-- Knowledge > Guides admin screen.
--
-- Only inserts rows that don't already exist (by title), so this is safe
-- to run even if some guides were added manually beforehand.

insert into public.knowledge_articles (title, body_markdown, published_at)
select v.title, v.body_markdown, v.published_at
from (values
  (
    'Uni-Light Nitrifying Bacteria: What It Does & How to Dose',
    $body$Uni-Light is a live nitrifying bacteria supplement for koi ponds and fish tanks. It seeds your filter with the bacteria that break down fish waste, so it isn't a fertiliser or a medicine — it's the biological filtration engine of your pond.

WHY YOUR POND NEEDS IT
Fish waste and uneaten food break down into ammonia, which is toxic to koi even at low levels. Nitrifying bacteria (Nitrosomonas) convert ammonia into nitrite — still toxic — and a second group (Nitrobacter) convert that nitrite into nitrate, which is far safer and removed gradually by water changes and plants. A pond only runs this cycle safely once enough of these bacteria are established on your filter media.

WHEN TO DOSE
• Setting up a brand-new pond or tank (cycling)
• After a big water change
• After cleaning or replacing filter media/sponges
• After a course of medication that may have killed off your bacteria colony
• Any time ammonia or nitrite tests read above zero

DOSAGE
4ml per 1,000 litres of pond water. Pour directly into the filter chamber or a high-flow area so it reaches the whole system quickly. Re-dose after major filter cleans, since scrubbing media washes away a large share of the colony.

IMPORTANT: UV STERILIZERS KILL BACTERIA TOO
A running UV sterilizer doesn't just kill algae and pathogens — it kills the free-floating bacteria you just dosed before they can settle on the filter media. If your pond has a UV unit, switch it off for 24–48 hours after dosing Uni-Light so the bacteria get a chance to colonise the filter.

Uni-Light is non-toxic to fish, plants and humans when used as directed — no need to remove fish before dosing.$body$,
    now() - interval '2 days'
  ),
  (
    'UV Sterilizers (UV-C Light) for Koi Ponds',
    $body$A UV sterilizer (also called a UV clarifier or "UV light") is an inline unit that passes pond water past a UV-C lamp inside a sealed chamber. It is a water-clarity and pathogen-control tool — it does not replace biological filtration, and it does not remove ammonia or nitrite.

WHAT IT ACTUALLY DOES
As water flows past the lamp, UV-C radiation damages the DNA of anything small enough to be fully exposed to the light as it passes: free-floating single-celled algae (the cause of "green water"), and many free-floating bacteria, fungal spores and parasite stages. It does not affect string algae attached to surfaces, and it has no effect on anything shielded inside a fish's gills or gut.

WHERE IT GOES IN THE SYSTEM
Install it AFTER your mechanical filter (so debris doesn't block UV exposure or shade organisms from the lamp) and BEFORE the water returns to the pond. Running it before the biological filter also means any dead bacterial clumps get trapped and removed rather than fouling the pond.

SIZING & FLOW RATE
UV sterilizers are rated for a specific flow rate (litres/hour) at a specific wattage — running water through faster than rated gives organisms too little exposure time to be killed, so match the unit to your pump's actual flow, not just your pond volume.

BULB LIFE
UV-C output drops well before the bulb visibly stops lighting up. Replace the bulb roughly every 8–12 months of continuous use (check the manufacturer's rated hours) even if it still glows — an old bulb gives you a false sense of protection while doing almost nothing.

INTERACTIONS TO KNOW
• Kills free-floating nitrifying bacteria too — switch it off for 24–48 hours after dosing a bacteria product like Uni-Light, or after adding pond-safe medication that needs to stay active in the water.
• Never look directly at an exposed UV-C lamp or let it shine on skin/eyes — always keep it inside its sealed housing.$body$,
    now() - interval '1 day'
  ),
  (
    'Anti-Chlorine / Dechlorinator: Why & How to Use It',
    $body$Tap water is treated with chlorine or chloramine to make it safe for people to drink — but both are toxic to fish, damaging gills and stripping the protective slime coat even at the concentrations used for household water. An anti-chlorine conditioner (dechlorinator) neutralises this before the water reaches your koi.

WHY YOU CAN'T SKIP IT
Chlorine alone off-gasses from water left standing for 24–48 hours, but chloramine (chlorine chemically bonded to ammonia, now common in many municipal supplies) does not off-gas the same way and stays active for days — "just letting it sit" is not a reliable substitute for a conditioner, especially with chloramine-treated tap water.

WHAT IT DOES
A dechlorinator like PetFran Multi Coat neutralises chlorine and chloramine on contact and, in "multi coat" style formulas, also adds a synthetic slime coat replacement to help fish recover from the stress of handling or minor scrapes during a water change.

WHEN TO USE IT
• Every partial water change — not just full refills
• Filling a new pond or tank for the first time
• Topping up water lost to evaporation with fresh tap water
• Any time you add tap water directly to a pond with fish already in it

HOW TO DOSE
Follow the product label's dosage by water volume (PetFran Multi Coat is sold as a 2L bottle sized for tap-water conditioning) — treat the new water either in a holding container before adding it, or dose directly into the pond as you fill, dosed for the full volume being added. Never estimate "a splash" — under-dosing leaves chlorine/chloramine active.

A NOTE ON CHLORAMINE
If your local water supply uses chloramine rather than plain chlorine, check that your conditioner explicitly claims to break the chlorine-ammonia bond (not just neutralise free chlorine) — otherwise the ammonia released can still spike your ammonia readings even after the chlorine itself is gone.$body$,
    now()
  )
) as v(title, body_markdown, published_at)
where not exists (
  select 1 from public.knowledge_articles existing where existing.title = v.title
);
