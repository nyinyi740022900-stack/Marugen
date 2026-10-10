# Commit and main push readiness

Checked: 2026-10-10

This is a source readiness check recorded before the user authorized commit/push. Pushing source does not deploy the app or backend.

## Verification

- Current branch: `main`; configured upstream remote: `origin` on GitHub.
- `git fetch origin` succeeded; local main and origin/main have no differing commits at the time of the check.
- Commit author name and email are configured.
- GitHub API confirms push permission, default branch `main`, and `main` is not protected at the time of the check.
- Full Flutter suite: 76 passed after the 2026-10-10 UI polish.
- Flutter analysis: no issues found.
- Order remarks server helper tests: 4 passed.
- Type checking succeeded for all seven changed/new Edge Functions: create-payment-intent, stripe-refund, reconcile-pending-orders, delete-account, easyparcel-book-shipment, easyparcel-webhook, send-order-notification.
- `git diff --check` passed.
- A filename/content scan of tracked and non-ignored candidate files found no matching Stripe secret, Supabase service-role JWT/secret, GitHub token, AWS access key or private key patterns. This is a targeted scan, not proof that every possible secret format is absent.
- Real iPhone preview: Profile build succeeded, installed and launched on the connected iPhone. An explicit temporary empty entitlement file was used only for this local preview because the Personal Apple team cannot provision Sign in with Apple. Production entitlement/project sources were preserved; this does not validate Apple sign-in or App Store release signing.
- iPad simulator preview: rebuilt after the UI polish; Shop and Guide layouts inspected natively. Guest Profile, Fulfillment, compact layouts, large text, light/dark themes and header safe areas are covered by widget tests. These latest UI changes have not been reinstalled on the real iPhone.
- Android debug build remains unverified. The online build was stopped after approximately six minutes waiting on dependency downloads. An offline check then failed because the Gradle Kotlin DSL plugin `6.4.2` was not cached. This is a dependency resolution blocker, not evidence of a successful native build or a source compilation failure.
- Retry the Android build when Gradle Plugin Portal dependencies can be downloaded; verify a signed release build separately before distributing the app.

## Readiness fixes

- Ignore generated `/android/build/` and `/output/` folders.
- Check missing Android release signing configuration only when release tasks are requested, so debug builds and IDE configuration are not blocked on a fresh checkout.
- Replace deprecated courier-rate RadioListTile selection properties with RadioGroup; analyzer now exits successfully.
- Correct environment documentation: Dart defines override values but do not remove the `.env` asset bundled by pubspec. Server secrets must never be put in either source.

## Proposed commit scope

Include app sources, platform configuration/assets, dependency files, tests, user/deployment docs, and corresponding backend functions/migrations. Keep `.env`, real environment JSON, signing keys, build outputs and generated previews out.

Local `.agents/`, `.codex/`, and `App Screenshort/` files are separate tooling/reference material and should not be blindly included in the app commit. Preserve these files locally.

The working tree contains multiple features, including pre-existing changes outside this chat. Split reviewable commits where practical: appearance and customer UX; order remarks with migration/function/tests; delivery/packing labels; refund/account deletion/reconciliation and native startup/release configuration. Avoid staging the entire directory without reviewing the file list.

## Before deploying

Main push only stores source in GitHub. It does not apply database migrations, deploy Edge Functions, or release an app.

The app contains new backend-dependent features. Verify migration history and deployment state before releasing it. In particular, 0048 adds refund tracking, 0049 configures pending-order reconciliation and requires Vault setup, and 0050 adds customer remarks plus revisions. Deploy matching functions before distributing the app. Live payment/refund/reconciliation and backend migration integration were not exercised by this source check.
