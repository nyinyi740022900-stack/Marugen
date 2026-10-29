# Closed beta 1.0.16 (21)

Requested update: owner Orders stale-list recovery and the earlier tab-spacing correction.

Orders now refreshes the shared paged/unbounded/fulfillment providers when selected in the primary navigation. The Orders AppBar also exposes a labeled Refresh orders action. Equal-width tabs remain in normal layouts and scrolling is retained only when current label metrics require it. Refresh makes read requests; no payment, booking, stock or order mutation is introduced.

Verification: the combined product/order/delivery/page suite passes **63 tests**; full Flutter analysis reports no issues. A controlled fixture deletes an order outside the displayed list and verifies that refresh removes it from both cached list paths while preserving the surviving order. Light/dark captures were inspected in the focused implementation pass. No new live payment or courier operation was performed.

Production-configured signed Android bundle built successfully (84.4 MB), with build name 1.0.16 and code 21. Signature verification returns exit 0 and `jar verified`. Artifact: `output/releases/marugen-1.0.16-21-orders-refresh.aab`. SHA-256: `2bff338de46dda6dbe36833d082c9b028ff15a1d1b9f6446c33170fccb4cfd98`.

Uploaded to the existing Closed testing — Alpha track with only bundle 21 included, and saved at 100% of existing testers. Submitted the change and independently observed **Changes in review — 21 (1.0.16)** in Publishing overview. Quick checks remain running; Google approval and tester availability are not yet claimed. Testers and countries are unchanged. Proof: `output/releases/beta21-in-review.png`.
