# Closed beta 1.0.9 (14): login viewport and kg labels

User requested Android login to fit the phone viewport and product weight labels to read kg.

Login now uses compact vertical spacing and a smaller brand header on phone-height viewports. Decorative subtitle is omitted in compact mode. Safe-area padding is not counted twice. Primary and social actions retain at least 48 logical pixels. All login methods, sign-up and privacy remain available. Keyboard / enlarged text retain scrolling. Product and variant weight input labels now both read kg; units and saved data are unchanged.

Verification: four new Android/iOS viewport regressions failed before the fix and passed after it; 360x740 and 390x844 with status/navigation insets. Focused responsive suite: 28 passed. Full production-configured suite: 244 passed. Light/dark rendered previews were inspected under output/login-review/. No physical-device login was performed.

Signed release 1.0.9 (14) was built using env/prod.json. Native binaries verified production publishable key and absence of dev banner text. Signature verified; analysis found no issues. Artifact: output/releases/marugen-1.0.9-14-login-kg.aab. SHA-256: f5d51e1d69315cb09af35cc964bd3216c08f164fc76caacd94a3f3b7f9c361e8. Current 1.0.8 (13) remains in Google review. Chrome native actions stopped responding and the extension timed out; user was asked to unlock / foreground Chrome. No release 14 upload or submission is verified.

Chrome resumed after user readiness confirmation. Alpha still shows 13 (1.0.8) in review. Created the next Alpha draft at releases/14/prepare without removing release 13.

## Submitted 2026-10-20

Uploaded the verified artifact (same SHA-256) to Alpha release 14. Google Play accepted version 14 (1.0.9); preview reported Ready to release and 100% rollout. Saved and sent the single Alpha change for review. Final state explicitly showed Changes in review / Closed testing - Alpha / 14 (1.0.9). Quick checks were still running. Tester and country settings and the production track were not changed. No review removal was performed. Evidence: output/releases/closed-beta-1.0.9-in-review.txt and .png.
