# Android closed beta 1.0.7 (12)

Prepared 2026-10-20 for the existing Closed testing — Alpha track. Version 1.0.6 (11) is serving. Release 12 was uploaded, validated and saved at 100% for the existing Alpha testers. Submission completed; Play Console shows **Changes in review — Closed testing Alpha — 12 (1.0.7)**. Automated quick checks were still running at verification; Google approval and tester availability remain pending. Evidence: output/releases/closed-beta-1.0.7-in-review.txt.

## Artifact

output/releases/marugen-1.0.7-12-delivery.aab, explicit version 1.0.7 / 12, existing signing certificate. SHA-256: e2f564e31ed7e510480c8d9d824baef2911e39bca982f88e0c0c4915f9aae665. Signature verification returned jar verified. The adjacent JSON records verification evidence. Pubspec retains the previous release version.

## Delivery changes

The user explicitly resolved the former restriction: all available couriers in S$. Owner prices show total delivery cost with the shared S$ formatter. Native SGD remains unchanged; verified MYR quotes use dated exchange metadata. Paid shipments remain locked to their accepted service and amount; other quotes are reference only. New checkout automatically selects the cheapest eligible door pickup / door delivery service. Installed older clients retain compatible TracX responses until updated.

Customer checkout shows estimated arrival dates and the buyer's SGD fee without carrier/contribution copy. Errors have Retry delivery and a 30-second client timeout. Server-trusted item kg multiplied by quantity determines weight. Uni-Light 500ml is 0.5 kg in live product and variant data. Courier shipping remains split 50/50 in integer cents; the shop fully covers live-fish delivery.

## Verification

Full Flutter: 240 passed. Focused Owner/checkout: 31 passed. Shipping/delivery server: 32 passed. Analysis, signed build and SQL boundaries passed. Migration 0060 is live with matching source hash, RLS enabled and no client shipping quote access. Four affected functions deployed. Final checkout anonymous app identity returned handler 401 Unauthorized.

No physical-device authenticated payment or billed shipment acceptance was performed. Singapore portal shows Singapore routing and S$ wallet amounts. Earlier same-day portal quotes show S$; fresh quote-results navigation later rendered blank, so fresh portal results have not been reconfirmed. App conversion does not change EasyParcel billing currency. Official documentation: https://github.com/easyparcel/easyparcel-cli/blob/main/README.md.
