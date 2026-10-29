# Closed beta 1.0.8 (13): production configuration correction

Submitted 2026-10-20 to the existing Closed testing — Alpha track. Play Console shows Changes in review for 13 (1.0.8); automated checks and Google approval remain pending.

## Confirmed issue

The 1.0.7 (12) release was built without the existing env/prod.json overrides. APP_ENV defaulted to dev, causing the red release banner; bundled .env contains a Stripe test publishable key. Production client configuration points to the same Supabase project and has a live Stripe publishable key. The user reports PaymentSheet fails before appearing. A client/server Stripe mode mismatch is consistent with that symptom, but the exact Stripe error for this attempt has not been retrieved. Do not assert successful payment acceptance.

## Corrected artifact

output/releases/marugen-1.0.8-13-production.aab was built with --dart-define-from-file=env/prod.json --build-name=1.0.8 --build-number=13. SHA-256: 66f458ec2ab0592716af158f21bcf317dd2573da14dd19e20eb3bacb3476a663.

All three native architecture binaries contain the intended production publishable key and omit the NON-PROD BACKEND banner text. No credentials are printed in evidence. Release signature verification returned jar verified. Production-configured Flutter suite: 240 passed. Build passed. Tests and release build must run sequentially because Flutter test can regenerate Android plugin registration.

All shipping improvements remain included. Production configuration uses live payments; no real charge was performed. Physical-device payment acceptance remains open.

## Submission blocker

Closed Alpha 1.0.7 (12) is already in review. Automatic approval review rejected removing that review because cancellation was not explicitly authorized and is unnecessary to prepare the corrected artifact. Do not bypass the rejection. Ask the user to authorize withdrawing the existing Alpha review and replacing it with this verified artifact. Existing testers, countries and production release track must be retained.

## Replacement authorized, browser connection blocked

The user explicitly approved withdrawing the existing 1.0.7 Alpha review and replacing it with verified 1.0.8 (13). Permission is no longer pending. Attempts to click Remove changes did not open a dialog or change the visible review. Native Chrome screenshots were blank and input produced no observable change. The Chrome extension call timed out and reset the runtime. A fresh native app binding and direct page navigation also did not respond. No upload or replacement submission was verified. User was asked to unlock the Mac, foreground Chrome and reconnect the extension. Do not request release permission again; resume from fresh Play Console state after connectivity returns.

## Browser resumed

After the user reconnected Chrome, the Alpha track showed 12 (1.0.7) already available to selected testers, released October 20 at 3:22 PM Singapore time. Publishing overview had no unpublished changes. Withdrawing a pending review was therefore no longer necessary. Created the next Alpha release 13 and uploaded the verified production-configured AAB. Existing testers/countries retained. Submission is in progress.

## Submission complete

Uploaded the verified AAB and confirmed version 13 (1.0.8), release Ready to release, existing Alpha track and 100% rollout. Saved and sent the single Alpha release change for review. Final Play Console state: Changes in review, Closed testing - Alpha, 13 (1.0.8). Quick checks still running at verification. Evidence: output/releases/closed-beta-1.0.8-in-review.txt and .png. Production track, tester configuration and countries were not changed. No payment was executed.
