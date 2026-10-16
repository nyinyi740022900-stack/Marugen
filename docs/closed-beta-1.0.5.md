# Android closed beta 1.0.5 (10)

Prepared 2026-10-16 for the existing Closed testing — Alpha track. Submitted for review the same day.

## Changes since 1.0.4 (9)

- Startup: removed the `runZonedGuarded` wrapper that raised a Flutter "Zone mismatch" error on every launch. Uncaught errors still reach Crashlytics through `PlatformDispatcher.onError`.
- Notifications: the OS permission prompt now appears after the promo popup is closed (or skipped), instead of stacking on top of it on first launch. The admin shell asks after its first paint.
- Login: visible back button when Login is pushed (Buy Now, Profile). Readable status-bar icons on its light background. The status-bar helper sets only status-bar fields, so the Android navigation bar is unchanged.
- Guide: Varieties / Care Guides / Services tabs are equal width on phone and tablet (regressed in 6bc95f4).
- Admin: raw `Error: $e` text in 12 screens replaced with plain-language messages (`friendlyErrorMessage`); load failures offer Retry.
- Local native acceptance tests now also run on iOS simulators.
- Admin: products that have been ordered can be deleted (migration 0056, `ON DELETE SET NULL`; order rows keep their snapshot). Delete failures are shown instead of failing silently. Order detail skips Reorder/Review for deleted products.
- Light theme: AlertDialog titles were white on white; now explicit.

## Verification

- `flutter analyze`: no issues. Unit tests pass except `packing_label_test`, which needs `pdfinfo` (poppler) and is not installed on this machine. Packing-label code is unchanged since 1.0.4.
- Android Pixel 7 emulator: guest integration test passed (shop, guest orders, profile light/dark, login back button, privacy policy).
- iOS simulators, local Supabase + Stripe test mode: iPhone 17 customer checkout (native SDK → webhook → paid, stock −1); owner admin on iPhone 17; staff admin on iPad Air 11"; dark mode; iPad landscape shop layout.
- iPhone 17 manual: promo → notification order, full-screen gallery and Login status bar, Login back.
- Release manifest contains `POST_NOTIFICATIONS`.

Not covered: interactive PaymentSheet card entry, 3DS, Google/Apple Pay, real Google/Apple sign-in, physical-device accessibility, courier booking.

## Build

Version 1.0.5+10, built with `env/prod.json` (same production client config as 1.0.3/1.0.4). It contains the **Stripe live publishable key**, so card payments by testers are real charges.

- Bundle: `output/releases/marugen-1.0.5-10.aab` (83.8 MB)
- SHA-256: `f72b0264a0de7456a7ee691b505d337be037e98b095c688387542c4cee711d25` (rebuilt after the product-delete fix, commit d125894)
- `jarsigner -verify`: jar verified (same 1049 protobuf-entry warnings as the accepted 1.0.4 bundle)
- Upload certificate SHA-1: `7E:9F:18:20:EC:82:F1:D8:47:35:F2:76:A9:7D:8F:84:4B:12:BC:17` (matches prior betas)

## Backend rollout

Migration **0056** must be applied to production before testers rely on product deletion. The CLI account lacks access to the linked project (403), and running production SQL was not permitted for the assistant, so the owner applies it in the Supabase SQL Editor. The statements are idempotent (`drop constraint if exists` / `add constraint`). Verified on the local stack: owner delete succeeds, customer delete is blocked by RLS, the paid order keeps product name, variant, price and total. No Edge Function change.

**Applied 2026-10-16** by the owner in the Supabase SQL Editor. The result shows `order_items_product_id_fkey` and `order_items_variant_id_fkey` with `confdeltype = n` (SET NULL). The migration history table was not updated. A later `supabase db push` would re-run 0056, which is idempotent.

Without 0056 the app still works. Deleting an ordered product then shows "This product has orders…" instead of silently failing.

## Submission status

1.0.4 (9) had been approved and was "Available to selected testers" before this submission.

The owner uploaded the bundle through the Play Console file picker; the assistant's browser bridge limits uploads to 10 MB. Play accepted **10 (1.0.5)**: API 24+, target SDK 36. Preview showed "Ready to release" with no loss of supported devices (Phone 12,379, Tablet 6,799). Rollout is 100% within the closed track. 9 (1.0.4) is not carried over.

Release notes (en-US) summarise the first-launch notification order, the Login back button and status bar, Guide tab alignment, and the admin error, delete and dialog fixes.

The release was saved and the single change submitted. Publishing overview shows **Changes in review**, with Google's quick checks still running (up to 13 minutes). Approval is not yet confirmed. Managed publishing is off. No Production release was submitted.
