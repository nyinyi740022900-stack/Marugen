-- 0017: Seed Marugen Lazada catalog as products + kg/size variants.
-- Prices in SGD from Lazada SG (Marugen Koi Farm). Stock default = 20.
-- Live koi use stock_quantity = 1 (unique animals; no variants).
-- Parent price for variant products = lowest variant price (display fallback).

begin;

-- Stable IDs so re-runs can be made idempotent with ON CONFLICT if needed later.
-- Products -------------------------------------------------------------------

insert into public.products (
  id, name, description, category, price, show_price, stock_quantity,
  image_urls, fish_details, is_sold
) values

-- 1–2 Live koi (no variants)
(
  'a1000001-0000-4000-8000-000000000001',
  'Japan Imported Koi Fish — Selection (Many Varieties & Sizes)',
  $desc$
Premium Japan-imported koi available at Marugen Koi Farm, Singapore. Many varieties and size ranges — Gosanke (Kohaku, Taisho Sanke, Showa) and non-Gosanke (Karashigoi, Ochiba Shigure, Chagoi, and more).

Each fish is individually selected for colour (beni / sumi), body conformation, and health. Farm visits are by appointment at 21 Neo Tiew Lane 1. Ideal for collectors building a pond collection or looking for show-quality stock.

Details:
• Origin: Japan import via Marugen Koi Farm
• Varieties: multiple (confirm on visit / WhatsApp)
• Size range: various sizes available
• Care: quarantine recommended; stable water parameters; quality diet (Saki-Hikari / JPD)
• Pickup / delivery: arrange with Marugen after purchase
  $desc$,
  'koi', 100.00, true, 1, '{}',
  jsonb_build_object(
    'variety', 'Assorted Japan import',
    'size_cm', null,
    'gender', null,
    'breeder', 'Japan / Marugen Koi Farm',
    'has_certificate', false
  ),
  false
),
(
  'a1000001-0000-4000-8000-000000000002',
  'Japan Imported Koi Fish — Premium Selection',
  $desc$
Higher-tier Japan-imported koi selection from Marugen Koi Farm. Suitable for hobbyists seeking stronger colour intensity, better pattern balance, and larger or more refined specimens.

Details:
• Origin: Japan import via Marugen Koi Farm
• Grade: premium selection listing
• Breeder lines: sourced from reputable Japanese farms
• Includes farm guidance on feeding, salt baths for new arrivals, and pond setup
• Appointment viewing available before finalising (WhatsApp / email)
  $desc$,
  'koi', 200.00, true, 1, '{}',
  jsonb_build_object(
    'variety', 'Assorted Japan import (premium)',
    'size_cm', null,
    'gender', null,
    'breeder', 'Japan / Marugen Koi Farm',
    'has_certificate', false
  ),
  false
),

-- 3 Marugen Special Mix
(
  'a1000001-0000-4000-8000-000000000003',
  'Marugen Special Mix High Growth + JPD Yamato Colour Enhancing Koi Food',
  $desc$
Marugen’s house blend: high-growth nutrition combined with JPD Yamato colour-enhancing formula. Designed for everyday feeding to support body growth and richer beni (red) development in koi.

Floating pellets; M and L pellet sizes available on request when ordering.

Details:
• Type: floating koi pellets (M / L)
• Focus: growth + colour enhancement
• Best for: home ponds and grow-out tanks
• Feeding tip: 2–3 times daily in warmer months; reduce in cool weather
• Storage: keep sealed, cool and dry
  $desc$,
  'fish_food', 8.80, true, 0, '{}', null, false
),

-- 4 JPD Fujizakura + Aka Fuji mixed
(
  'a1000001-0000-4000-8000-000000000004',
  'JPD Mixed Koi Food — Fujizakura Health + Aka Fuji Colour Enhancing',
  $desc$
Japanese Premium Diet (JPD) mixed bag combining Fujizakura health formula with Aka Fuji colour enhancing. Supports overall condition while boosting red pigmentation.

Floating pellets; M/L sizes. Also available as 20kg sinking (6mm only).

Details:
• Brand: JPD (Japan)
• Blend: Fujizakura (health) + Aka Fuji (colour)
• Form: floating (most sizes) / sinking 6mm (20kg)
• Use: daily staple for colour-focused ponds
  $desc$,
  'fish_food', 42.80, true, 0, '{}', null, false
),

-- 5 JPD Shori + Aka Fuji mixed
(
  'a1000001-0000-4000-8000-000000000005',
  'JPD Mixed Koi Food — Shori High Growth + Aka Fuji Colour Enhancing',
  $desc$
JPD Shori high-growth diet blended with Aka Fuji colour enhancer. Ideal when you want faster growth without sacrificing colour quality.

Floating M/L, plus 20kg sinking Shori high-growth (6mm).

Details:
• Brand: JPD
• Blend: Shori (growth) + Aka Fuji (colour)
• Form: floating / sinking 20kg option
• Best season: active growth months
  $desc$,
  'fish_food', 44.80, true, 0, '{}', null, false
),

-- 6 JPD Shori High Growth + Colour (single line SKU)
(
  'a1000001-0000-4000-8000-000000000006',
  'JPD Shori High Growth + Colour Koi Food',
  $desc$
Dedicated JPD Shori high growth + colour formula (floating). Trusted Japanese farm feed for championship-oriented grow-out.

Details:
• Brand: JPD Shori
• Form: floating pellets (M/L)
• Pack: 15kg
• Focus: growth with colour support
  $desc$,
  'fish_food', 197.00, true, 0, '{}', null, false
),

-- 7 Fujiyama wheat germ
(
  'a1000001-0000-4000-8000-000000000007',
  'JPD Fujiyama Wheat Germ + Fish Meal Health Diet Koi Food',
  $desc$
JPD Fujiyama wheat germ + fish meal health diet. Gentler staple suited to cooler weather and year-round maintenance feeding while keeping condition.

Details:
• Brand: JPD Fujiyama
• Ingredients focus: wheat germ + fish meal
• Form: floating (M/L)
• Pack: 15kg
• Best for: cooler months / recovery / maintenance
  $desc$,
  'fish_food', 118.00, true, 0, '{}', null, false
),

-- 8 Shogun whitening
(
  'a1000001-0000-4000-8000-000000000008',
  'JPD Shogun Whitening Wheat Germ Koi Food',
  $desc$
JPD Shogun whitening wheat germ diet — supports clean shiroji (white ground) while maintaining health through wheat-germ nutrition.

Details:
• Brand: JPD Shogun
• Focus: whitening / shiroji quality + wheat germ health
• Form: floating (M/L)
• Pack: 15kg
  $desc$,
  'fish_food', 198.00, true, 0, '{}', null, false
),

-- 9 Aka Fuji colour booster
(
  'a1000001-0000-4000-8000-000000000009',
  'JPD Aka Fuji Colour Booster Health Diet Koi Food',
  $desc$
JPD Aka Fuji colour booster health diet. Formulated to intensify beni while supporting overall koi health — used widely by serious hobbyists and farms.

Details:
• Brand: JPD Aka Fuji
• Focus: colour booster + health
• Form: floating (M/L)
• Pack: 15kg
  $desc$,
  'fish_food', 225.00, true, 0, '{}', null, false
),

-- 10 Yokozuna
(
  'a1000001-0000-4000-8000-00000000000a',
  'JPD Yokozuna Silkworm + Wheat Germ + Fish Meal Koi Food',
  $desc$
JPD Yokozuna well-balanced high-protein growth & health diet with silkworm, wheat germ, and fish meal. Premium balanced feed for serious growth programmes.

Details:
• Brand: JPD Yokozuna
• Protein sources: silkworm + fish meal + wheat germ
• Form: floating (M/L)
• Pack: 15kg
  $desc$,
  'fish_food', 198.00, true, 0, '{}', null, false
),

-- 11 Medicarp Max
(
  'a1000001-0000-4000-8000-00000000000b',
  'JPD Medicarp Max Health Care Premium Koi Food',
  $desc$
JPD Medicarp Max premium health-care diet. Formulated for koi needing extra nutritional support and robust condition.

Details:
• Brand: JPD Medicarp Max
• Focus: premium health care
• Form: floating (M/L)
• Pack: 10kg
  $desc$,
  'fish_food', 220.00, true, 0, '{}', null, false
),

-- 12 Yamato repackaged
(
  'a1000001-0000-4000-8000-00000000000c',
  'JPD Yamato Colour Enhancing High Growth Koi Food (Repackaged)',
  $desc$
Affordable JPD Yamato colour-enhancing high-growth koi food, repackaged in smaller sizes for home ponds and trial feeding.

Details:
• Brand: JPD Yamato (repackaged)
• Focus: colour + growth
• Form: floating (M/L)
• Sizes: 500g to 3kg
  $desc$,
  'fish_food', 12.80, true, 0, '{}', null, false
),

-- 13 Mud Booster
(
  'a1000001-0000-4000-8000-00000000000d',
  'JPD Mud Booster for Japanese Koi Fish',
  $desc$
JPD Mud Booster — specialised supplement used in mud-pond style conditioning programmes to help refine skin quality and support traditional Japanese grow-out practices.

Details:
• Brand: JPD
• Use: mud pond / conditioning programmes
• Pack: 2kg
• Follow Marugen guidance for dosage and schedule
  $desc$,
  'fish_food', 56.50, true, 0, '{}', null, false
),

-- 14 Saki-Hikari Mixed
(
  'a1000001-0000-4000-8000-00000000000e',
  'Saki-Hikari Mixed Koi Food — High Growth + Colour Enhancing',
  $desc$
Hikari Saki mixed diet combining Saki high growth with Saki colour enhancing. Professional-grade Japanese feed used by top breeders for show preparation and daily excellence.

Details:
• Brand: Hikari Saki
• Blend: High Growth + Colour Enhancing
• Form: floating, M size
• Feeding: follow Hikari guidelines; avoid overfeeding
  $desc$,
  'fish_food', 48.00, true, 0, '{}', null, false
),

-- 15 Saki Growth
(
  'a1000001-0000-4000-8000-00000000000f',
  'Saki-Hikari Growth Diet Koi Food',
  $desc$
Saki-Hikari Growth Diet — floating pellets focused on efficient, healthy growth for juvenile and grow-out koi.

Details:
• Brand: Hikari Saki Growth
• Form: floating (M/L)
• Pack: 15kg
  $desc$,
  'fish_food', 200.00, true, 0, '{}', null, false
),

-- 16 Saki Colour
(
  'a1000001-0000-4000-8000-000000000010',
  'Saki-Hikari Color Enhancing Koi Food',
  $desc$
Saki-Hikari Color Enhancing diet with spirulina-rich formulation to deepen beni and overall colour intensity while maintaining health.

Details:
• Brand: Hikari Saki Color
• Focus: colour enhancement
• Form: floating (M/L)
• Pack: 15kg
  $desc$,
  'fish_food', 230.00, true, 0, '{}', null, false
),

-- 17 BSFL
(
  'a1000001-0000-4000-8000-000000000011',
  'Dried Black Soldier Fly Larvae — Koi & Arowana Treat',
  $desc$
Dried black soldier fly larvae (BSFL) — high-protein natural treat for koi, arowana, and other ornamental fish. Also suitable as occasional enrichment for birds and reptiles.

Details:
• Protein-rich insect feed
• Use as treat / supplement (not sole diet)
• Animals: koi, arowana, goldfish, birds, reptiles
• Store airtight to keep crisp
  $desc$,
  'fish_food', 12.80, true, 0, '{}', null, false
),

-- 18 Sea salt
(
  'a1000001-0000-4000-8000-000000000012',
  'Natural Sea Salt for Ornamental Fish',
  $desc$
Natural sea salt for freshwater ornamental fish (koi, goldfish, etc.) and marine setups. Helps mineral balance and osmotic regulation; useful when introducing new fish or reducing chlorine/chloramine stress (follow safe dosing).

Details:
• Use: freshwater ornamental & marine
• Benefits: mineral balance, osmotic support
• Tip: dissolve fully before adding to pond/tank
• Not a substitute for dechlorinator in all cases — pair with proper water prep
  $desc$,
  'accessories', 15.00, true, 0, '{}', null, false
),

-- 19 Oyster shells
(
  'a1000001-0000-4000-8000-000000000013',
  'Oyster Shells — Filter Media & pH Buffer',
  $desc$
Crushed oyster shells for koi ponds and fish tanks — acts as filter media and a gentle pH buffer, slowly releasing calcium carbonate to stabilise water chemistry.

Details:
• Pack: 6kg
• Use: canister / pond filter chambers
• Benefit: pH buffering + bio-media surface
• Organic / food-contact grade sourcing (farm standard)
  $desc$,
  'accessories', 27.00, true, 0, '{}', null, false
),

-- 20 Uni-Light
(
  'a1000001-0000-4000-8000-000000000014',
  'Uni-Light Nitrifying Beneficial Bacteria',
  $desc$
Uni-Light nitrifying beneficial bacteria for koi ponds and fish tanks. Establishes and supports biological filtration by helping break down harmful ammonia/nitrite waste.

Dosage: 4ml per 1000 litres of water (adjust for bioload and after filter maintenance).

Details:
• Volume: 500ml
• Dosage: 4ml / 1000L
• Use after water changes, new setups, or filter cleaning
• Non-toxic when used as directed
  $desc$,
  'accessories', 27.00, true, 0, '{}', null, false
),

-- 21 PetFran anti-chlorine
(
  'a1000001-0000-4000-8000-000000000015',
  'PetFran Multi Coat Anti Chlorine Solution',
  $desc$
PetFran Multi Coat anti-chlorine water conditioner (2L). Neutralises chlorine/chloramine and supports safer water changes for ornamental fish ponds and tanks.

Details:
• Volume: 2L
• Use: tap water conditioning before adding to pond/tank
• Follow label dosage by water volume
  $desc$,
  'accessories', 27.00, true, 0, '{}', null, false
),

-- 22 Hikari container
(
  'a1000001-0000-4000-8000-000000000016',
  'Hikari Koi Food Container',
  $desc$
Official Hikari koi food storage container — keeps pellets dry, sealed, and portion-ready for daily feeding.

Details:
• Accessory for Hikari / Saki pellet storage
• Helps prevent moisture and pest exposure
  $desc$,
  'accessories', 35.00, true, 20, '{}', null, false
);

-- Variants ------------------------------------------------------------------

insert into public.product_variants (
  id, product_id, label, price, stock_quantity, sku, sort_order
) values

-- Marugen Special Mix
('b1000001-0000-4000-8000-000000000001', 'a1000001-0000-4000-8000-000000000003', '300g',   8.80,  20, 'MRG-MIX-300G', 10),
('b1000001-0000-4000-8000-000000000002', 'a1000001-0000-4000-8000-000000000003', '500g',  10.80,  20, 'MRG-MIX-500G', 20),
('b1000001-0000-4000-8000-000000000003', 'a1000001-0000-4000-8000-000000000003', '1kg',   18.80,  20, 'MRG-MIX-1KG',  30),
('b1000001-0000-4000-8000-000000000004', 'a1000001-0000-4000-8000-000000000003', '1.5kg', 26.80,  20, 'MRG-MIX-1.5KG', 40),
('b1000001-0000-4000-8000-000000000005', 'a1000001-0000-4000-8000-000000000003', '2kg',   33.80,  20, 'MRG-MIX-2KG',  50),
('b1000001-0000-4000-8000-000000000006', 'a1000001-0000-4000-8000-000000000003', '3kg',   46.80,  20, 'MRG-MIX-3KG',  60),
('b1000001-0000-4000-8000-000000000007', 'a1000001-0000-4000-8000-000000000003', '5kg',   62.80,  20, 'MRG-MIX-5KG',  70),
('b1000001-0000-4000-8000-000000000008', 'a1000001-0000-4000-8000-000000000003', '10kg',  96.80,  20, 'MRG-MIX-10KG', 80),
('b1000001-0000-4000-8000-000000000009', 'a1000001-0000-4000-8000-000000000003', '15kg', 118.80,  20, 'MRG-MIX-15KG', 90),

-- JPD Fujizakura + Aka Fuji
('b1000001-0000-4000-8000-000000000010', 'a1000001-0000-4000-8000-000000000004', '2kg',                 42.80, 20, 'JPD-FZ-AF-2KG',  10),
('b1000001-0000-4000-8000-000000000011', 'a1000001-0000-4000-8000-000000000004', '3kg',                 62.80, 20, 'JPD-FZ-AF-3KG',  20),
('b1000001-0000-4000-8000-000000000012', 'a1000001-0000-4000-8000-000000000004', '5kg',                 95.80, 20, 'JPD-FZ-AF-5KG',  30),
('b1000001-0000-4000-8000-000000000013', 'a1000001-0000-4000-8000-000000000004', '10kg',               168.80, 20, 'JPD-FZ-AF-10KG', 40),
('b1000001-0000-4000-8000-000000000014', 'a1000001-0000-4000-8000-000000000004', '15kg',               208.80, 20, 'JPD-FZ-AF-15KG', 50),
('b1000001-0000-4000-8000-000000000015', 'a1000001-0000-4000-8000-000000000004', '20kg (Sinking 6mm)', 265.00, 20, 'JPD-FZ-20KG-SINK', 60),

-- JPD Shori + Aka Fuji mixed
('b1000001-0000-4000-8000-000000000016', 'a1000001-0000-4000-8000-000000000005', '2kg',                 44.80, 20, 'JPD-SH-AF-2KG',  10),
('b1000001-0000-4000-8000-000000000017', 'a1000001-0000-4000-8000-000000000005', '3kg',                 63.80, 20, 'JPD-SH-AF-3KG',  20),
('b1000001-0000-4000-8000-000000000018', 'a1000001-0000-4000-8000-000000000005', '5kg',                 98.80, 20, 'JPD-SH-AF-5KG',  30),
('b1000001-0000-4000-8000-000000000019', 'a1000001-0000-4000-8000-000000000005', '10kg',               171.80, 20, 'JPD-SH-AF-10KG', 40),
('b1000001-0000-4000-8000-00000000001a', 'a1000001-0000-4000-8000-000000000005', '15kg',               211.80, 20, 'JPD-SH-AF-15KG', 50),
('b1000001-0000-4000-8000-00000000001b', 'a1000001-0000-4000-8000-000000000005', '20kg (Sinking 6mm)', 270.00, 20, 'JPD-SH-20KG-SINK', 60),

-- JPD Shori High Growth + Colour 15kg
('b1000001-0000-4000-8000-00000000001c', 'a1000001-0000-4000-8000-000000000006', '15kg', 197.00, 20, 'JPD-SHORI-COLOUR-15KG', 10),

-- Fujiyama 15kg
('b1000001-0000-4000-8000-00000000001d', 'a1000001-0000-4000-8000-000000000007', '15kg', 118.00, 20, 'JPD-FUJIYAMA-15KG', 10),

-- Shogun 15kg
('b1000001-0000-4000-8000-00000000001e', 'a1000001-0000-4000-8000-000000000008', '15kg', 198.00, 20, 'JPD-SHOGUN-15KG', 10),

-- Aka Fuji booster 15kg
('b1000001-0000-4000-8000-00000000001f', 'a1000001-0000-4000-8000-000000000009', '15kg', 225.00, 20, 'JPD-AKA-FUJI-15KG', 10),

-- Yokozuna 15kg
('b1000001-0000-4000-8000-000000000020', 'a1000001-0000-4000-8000-00000000000a', '15kg', 198.00, 20, 'JPD-YOKOZUNA-15KG', 10),

-- Medicarp Max 10kg
('b1000001-0000-4000-8000-000000000021', 'a1000001-0000-4000-8000-00000000000b', '10kg', 220.00, 20, 'JPD-MEDICARP-10KG', 10),

-- Yamato repackaged (tiered from Lazada range listing; 3kg ≈ listed $33.80)
('b1000001-0000-4000-8000-000000000022', 'a1000001-0000-4000-8000-00000000000c', '500g', 12.80, 20, 'JPD-YAMATO-RPK-500G', 10),
('b1000001-0000-4000-8000-000000000023', 'a1000001-0000-4000-8000-00000000000c', '1kg',  18.80, 20, 'JPD-YAMATO-RPK-1KG',  20),
('b1000001-0000-4000-8000-000000000024', 'a1000001-0000-4000-8000-00000000000c', '2kg',  26.80, 20, 'JPD-YAMATO-RPK-2KG',  30),
('b1000001-0000-4000-8000-000000000025', 'a1000001-0000-4000-8000-00000000000c', '3kg',  33.80, 20, 'JPD-YAMATO-RPK-3KG',  40),

-- Mud Booster 2kg
('b1000001-0000-4000-8000-000000000026', 'a1000001-0000-4000-8000-00000000000d', '2kg', 56.50, 20, 'JPD-MUD-BOOST-2KG', 10),

-- Saki-Hikari Mixed
('b1000001-0000-4000-8000-000000000027', 'a1000001-0000-4000-8000-00000000000e', '2kg',  48.00, 20, 'SAKI-MIX-2KG',  10),
('b1000001-0000-4000-8000-000000000028', 'a1000001-0000-4000-8000-00000000000e', '3kg',  69.00, 20, 'SAKI-MIX-3KG',  20),
('b1000001-0000-4000-8000-000000000029', 'a1000001-0000-4000-8000-00000000000e', '5kg', 105.00, 20, 'SAKI-MIX-5KG',  30),
('b1000001-0000-4000-8000-00000000002a', 'a1000001-0000-4000-8000-00000000000e', '10kg', 180.00, 20, 'SAKI-MIX-10KG', 40),
('b1000001-0000-4000-8000-00000000002b', 'a1000001-0000-4000-8000-00000000000e', '15kg', 225.00, 20, 'SAKI-MIX-15KG', 50),

-- Saki Growth 15kg
('b1000001-0000-4000-8000-00000000002c', 'a1000001-0000-4000-8000-00000000000f', '15kg', 200.00, 20, 'SAKI-GROWTH-15KG', 10),

-- Saki Color 15kg
('b1000001-0000-4000-8000-00000000002d', 'a1000001-0000-4000-8000-000000000010', '15kg', 230.00, 20, 'SAKI-COLOR-15KG', 10),

-- BSFL (300g–3kg; mid sizes interpolated from Lazada range listing ~$48.80)
('b1000001-0000-4000-8000-00000000002e', 'a1000001-0000-4000-8000-000000000011', '300g', 12.80, 20, 'BSFL-300G', 10),
('b1000001-0000-4000-8000-00000000002f', 'a1000001-0000-4000-8000-000000000011', '500g', 18.80, 20, 'BSFL-500G', 20),
('b1000001-0000-4000-8000-000000000030', 'a1000001-0000-4000-8000-000000000011', '1kg',  28.80, 20, 'BSFL-1KG',  30),
('b1000001-0000-4000-8000-000000000031', 'a1000001-0000-4000-8000-000000000011', '2kg',  48.80, 20, 'BSFL-2KG',  40),
('b1000001-0000-4000-8000-000000000032', 'a1000001-0000-4000-8000-000000000011', '3kg',  68.80, 20, 'BSFL-3KG',  50),

-- Sea salt: 4kg / 9kg / 18kg (9kg = Lazada listed $22; 18kg proportional bulk)
('b1000001-0000-4000-8000-000000000033', 'a1000001-0000-4000-8000-000000000012', '4kg',  15.00, 20, 'SALT-4KG',  10),
('b1000001-0000-4000-8000-000000000034', 'a1000001-0000-4000-8000-000000000012', '9kg',  22.00, 20, 'SALT-9KG',  20),
('b1000001-0000-4000-8000-000000000035', 'a1000001-0000-4000-8000-000000000012', '18kg', 40.00, 20, 'SALT-18KG', 30),

-- Oyster shells 6kg
('b1000001-0000-4000-8000-000000000036', 'a1000001-0000-4000-8000-000000000013', '6kg', 27.00, 20, 'OYSTER-6KG', 10),

-- Uni-Light 500ml
('b1000001-0000-4000-8000-000000000037', 'a1000001-0000-4000-8000-000000000014', '500ml', 27.00, 20, 'UNILIGHT-500ML', 10),

-- PetFran 2L
('b1000001-0000-4000-8000-000000000038', 'a1000001-0000-4000-8000-000000000015', '2L', 27.00, 20, 'PETFRAN-AC-2L', 10);

commit;
