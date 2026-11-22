# Product card redesign — clean, button-free (Lazada-style)

Status: plan, not started. Date: 2026-11-21.

## Goal

The Shop grid card becomes a quiet "browse" card: photo, name, price, one
line of social proof. No buttons on the card. Tapping anywhere opens the
product page, which already has Add to cart / Buy now / Chat / heart.
Must look and feel native on both Android and iOS, in light and dark, at
large text sizes.

## What the card shows (top to bottom)

1. **Photo** — square, edge to edge, rounded corners with the card. On it:
   - top-left: variety tag (koi only) and `-N%` tag when on sale, stacked
   - bottom-left: `Only N left` (restockables, stock ≤ 3) — unchanged rule
   - nothing else: no heart, no cart, no buy pill, no play icon
2. **Name** — 2 lines, 14 pt semibold, always reserves 2 lines so prices
   line up across a row (keep the current `ConstrainedBox` trick)
3. **Price row** — accent colour, 15 pt bold. On sale: struck original
   beside it (hidden above 1.3× text scale, as now). Variants: `From S$…`.
   Contact-for-price: muted `Contact for price`.
4. **Proof line** — one muted 11 pt line, parts joined with ` · `:
   `★ 4.8 (152)` · `991 sold` · (koi) `45 cm · Male`. When nothing applies
   the line is still reserved so cards stay the same height.
5. Nothing under that. No delivery estimate on the card (it moves to the
   product page's existing delivery block; the card body gets ~48 px
   shorter, which also fixes the leftover white band).

Out-of-stock / Sold: photo dimmed to 55 % with a small `Sold` / `Out of
stock` tag bottom-left; price turns muted. No overlay button.

## Visual tokens

- Card: `surface` background, radius `AppRadius.md`, **no drop shadow** on
  the grid; a 1 px `border` hairline in light, none in dark (Lazada-flat
  look, less visual noise with many cards). Padding 10 / 8 / 10 / 10.
- Photo placeholder: `surfaceMuted` with a soft shimmer while loading.
- Tags: 10 pt, 4 px radius, same `_Tag` widget as today.
- Grid gutter 12 px (was 16) so two cards get wider photos on 360-wide
  Android phones; outer padding stays 16.

## Interaction (both platforms)

- Whole card is one tap target → product page. `PressScale` press-down
  (0.97, spring) is the only feedback on iOS (`NoSplash`, already set in
  the theme); Android keeps `InkSparkle` ripple under the same
  `PressScale`. No long-press menu.
- Semantics: one merged label per card, e.g.
  `Kohaku 45 cm, S$320, rating 4.8 of 5 from 152 reviews, 991 sold`,
  button role. Remove the per-button tooltips.
- Light haptic on tap stays off (navigation, not an action).

## Android / iOS parity checklist

- Typography already branches in `app_theme.dart` (SF Text with HIG
  tracking on Apple, Roboto on Android). Card uses theme text styles only,
  no hard-coded families.
- Test matrix: iPhone 17 Pro Max sim, iPhone SE width (375), Pixel 7 AVD
  (360 dp), Pixel tablet / iPad 2-up → 3/4 columns via the existing
  breakpoint code. Text scale 1.0, 1.3, 2.0. Light + dark.
- Images: keep `SizedNetworkImage` (cache + decode size); confirm no
  jank on Pixel 7 when scrolling 40 cards.
- Safe areas / bottom tab inset unchanged (`ProductGrid` already uses
  `BottomInset`).

## Code changes

| Area | Change |
|---|---|
| `lib/shared/widgets/product_card.dart` | Remove `_CardActionButtons`, `_BuyPill`, `_QuickAddButton`, `_RoundIconButton`, `_FavoriteButton`, `_DeliveryEstimateLabel`. Fold `_StatsRow` + `_FishFactsLabel` into one `_ProofLine`. Add merged `Semantics`. Drop `showFavoriteToggle` param (callers: shop, wishlist, admin products, PDP "related"). |
| `lib/shared/widgets/product_grid.dart` | `productCardExtent`: remove the 48 px action row and delivery measurement; new formula = photo + 8 + name(2 lines) + 4 + price + 3 + proof + 10. Gutter 12. |
| `lib/features/shop/presentation/product_detail_screen.dart` | Make sure heart + delivery estimate are prominent there, since the card no longer shows them (heart already in the app bar; delivery block exists). |
| `lib/features/wishlist/presentation/wishlist_screen.dart` | Remove button already covers removal; no change beyond dropping the param. |
| `lib/features/admin/products/admin_products_screen.dart` | Drop the param; admin keeps its own overflow actions. |
| Unused code | `supportsQuickAdd` on `Product` and the card-only purchase-intent path may become unused; keep `supportsQuickAdd` if PDP uses it, otherwise delete. |

## Tests to update / add

- `test/catalog_accessibility_test.dart` — remove the `Add … to cart`
  48 pt target assertions and the `Buy Chosen fish now` tap; replace with
  the merged semantics label check and a whole-card tap → route test.
- `test/p2_quick_fixes_test.dart` — the `Buy Kohaku now` tooltip test goes.
- `test/catalog_card_refinement_test.dart`, `responsive_followup_test.dart`,
  `dark_shared_test.dart` — re-pin heights: no white band under the proof
  line at 1×, 1.3×, 2× on 320/360/390 widths; price never truncated.
- New: golden-free layout test that two cards in a row have equal
  heights with and without rating / sold / sale.
- `flutter test` full run, `flutter analyze`, then simulator + Pixel 7
  screenshots of Shop, Wishlist, Admin › Products, PDP related row.

## Risks / decisions

- **Losing quick-add and Buy now from the grid** adds one tap to buy.
  Accepted for a cleaner shop; PDP has the big CTAs.
- **Heart on the card**: plan removes it (Lazada has none). If the owner
  wants it back, add a 32 px top-right heart only — still no cart button.
- Sold-count display depends on `soldCount` being populated for the
  catalog; it already is (used by `_StatsRow`).

## Order of work

1. Card widget rewrite + grid extent (one commit).
2. Callers + remove dead code.
3. Tests.
4. Device/simulator pass on both platforms, screenshots into
   `App Screenshort/` for comparison.
5. Commit, push, PR.
