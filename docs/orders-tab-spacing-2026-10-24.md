# Orders tab spacing regression

The previous accessibility correction made the owner Orders TabBar scrollable at every size, with start alignment. This grouped All, Fulfillment and Payments on the left even when there was sufficient room for equal columns.

The AppBar now measures the three labels using the current theme, direction and user text scaler. If the widest label plus horizontal padding fits each third of the available width, tabs fill three equal columns. Otherwise the existing scrollable arrangement preserves complete labels. Business behavior, destinations, colors and copy are unchanged.

Two new regression tests first failed against the always-scrollable implementation. The fixed product/order suite passes **17 tests** in light/dark, including the existing compact 320-pixel, 2× text checks. Two opt-in renders at 390 pixels and normal text pass with the installed app font and confirm equal centers. Full Flutter analysis reports no issues; whitespace and formatting checks pass.

Inspected light/dark evidence: `output/ui-final-product-order/order-tabs-spaced-Brightness.light.png` and `order-tabs-spaced-Brightness.dark.png`. These are actual widget renders with fake empty order responses; no live owner writes or external transactions occur.

Android production beta **1.0.15 (20)** builds successfully (84.4 MB). Signature verification returns exit 0 and `jar verified`. Artifact: `output/releases/marugen-1.0.15-20-orders-tabs.aab`; SHA-256: `13985633ee78c457efae9ef83a8c8b555b3a7de7788735da64d4ca6c38eb7c39`. Uploaded to existing Closed testing — Alpha, saved at 100% of existing testers, only bundle 20 included. Review submission was attempted with confirmation, but the console repeatedly returns to **Changes not yet submitted for review** without an error, including after refresh. Quick checks remain running. Do not claim review acceptance or availability. Proof: `output/releases/beta20-pending-review.png`.

Follow-up on similar defects: all four TabBar call sites were inventoried (owner Orders, owner Knowledge, customer Knowledge and PDP). The two Knowledge surfaces already use fixed equal columns; PDP has four content sections in an intentional scrollable strip. Related page/catalog/knowledge regressions pass **41 tests**. This does not establish absence of every visual defect. The new Orders tests assert equal tab centers, because overflow-only checks had missed this spacing regression.

Later verification while preparing the requested refresh update: the Alpha track now authoritatively shows **Release 20 (1.0.15) in review**. The earlier pending state above records the observed state at that time; the submission subsequently progressed.
