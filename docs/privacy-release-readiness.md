# Privacy and Closed beta 1.0.3 readiness

Approved privacy/support email: **marugenfishfarmaiagent@gmail.com**.

The app and generated public pages use the same policy text in
`lib/features/legal/privacy_content.dart`. Regenerate with
`python3 scripts/generate_privacy_pages.py` after editing that text.

## Deployment sequence

1. Sign in to the Cloudflare account owning `marugen.pages.dev` and locate its actual source/deployment. Do not replace the entire website with the legal-only `docs` directory. Preserve the existing homepage, script, styles and media.
2. Copy `docs/privacy-policy/index.html` and `docs/data-deletion/index.html` into the corresponding paths of the existing site. Run `scripts/patch_website_contact.py` against its homepage to replace the example email and correct the farm location.
3. Preview, deploy and verify all three public direct URLs. Confirm the mail links point to the approved email and deletion can be requested without signing in or reinstalling the app.
4. Apply **0051_account_deletion.sql** to the Marugen Supabase project `gexgcwdkbeythrnqmihe`. This only changes constraints/policies; it does not delete any existing account or order.
5. Deploy `delete-account` and `send-order-notification`. Check a disposable customer deletion with retained orders/promo history and multiple avatars. Do not test by deleting a real customer or staff account.
6. Rebuild the signed Android 1.0.3+8 bundle without `--no-pub`, verify the signature and record its fresh checksum. The older UI-only bundle must not be uploaded as the privacy update.
7. Verify Play Console Privacy Policy and Data safety deletion fields use the public direct URLs, and reconcile Data safety disclosures with the policy (account/contact/address, financial/order data, reviews/photos, app usage, diagnostics and device identifiers).
8. Upload to the existing Alpha draft release 8, include privacy and deletion changes in English release notes, review the exact pending changes, and submit Closed beta for review.

## Retained records

Auth accounts and profiles are deleted rather than banned. Addresses, wishlists,
reviews and inbox notifications cascade with the profile. Personal avatar objects
are removed through the Storage API. Business order/delivery/payment records remain,
with their customer references detached; their retained recipient details are
explicitly disclosed in the policy. Promo counts and status audit records remain.
Staff accounts require a support workflow to preserve shop-owned assets.

The five-year business-record explanation follows
[IRAS record keeping requirements](https://www.iras.gov.sg/taxes/corporate-income-tax/basics-of-corporate-income-tax/record-keeping-requirements).
Manual privacy requests and retention reviews must be handled by the shop;
this release does not introduce an automated five-year purge job.

## Access blockers observed on 13 October 2026

Cloudflare and Supabase browser sessions require sign-in. The existing Supabase CLI
session returns HTTP 403 for the linked project. After browser sign-in, migration 0051 and both functions were deployed and the rollback-only database fixture test passed. The website is owned by the tester team, not this Cloudflare account. The user subsequently authorized Closed beta submission with the existing website links after consulting that team. The new public policy pages remain ready for the team to deploy; the old website text has not been certified as complete or approved by Google.

## Policy references

- [Google Play User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [Google Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)
- [Supabase user deletion and storage ownership](https://supabase.com/docs/guides/auth/managing-user-data)
