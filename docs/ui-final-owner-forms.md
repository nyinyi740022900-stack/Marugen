# Owner editor final acceptance — 23 October 2026

## Covered surfaces and evidence

This bounded pass preserves Marugen's existing palette, typography, copy and bottom-sheet patterns. `test/final_owner_forms_test.dart` renders the actual owner Variety, Guide, Service and Promo Code sheets using fixture data and a fake Supabase client. No live credentials or live persistence are used.

All four editors are exercised in **create and edit** at 320×740 logical pixels, 2× text, light and dark, with a synthetic 250-pixel keyboard inset. Save/Publish is scrolled into view and hit-tested. Empty required values are rejected without sending a request. Valid populated edits simulate a failed request and retain the sheet with visible retry feedback and an enabled action. Additional cases cover optional service-price validation, malformed promo usage limits, percent values above 100, growth-stage input width and add/remove, clearing expiry, and opening/cancelling the date picker for an expiry from 2020.

## Material corrections

- Variety category and Promo discount dropdowns constrain their selected content instead of overflowing horizontally. Promo selection can use two lines and scales its row height, preserving the complete “Fixed amount off” label at 2× text.
- Variety Growth Stages and Add stage wrap instead of overflowing. At compact enlarged text, stage photo/removal controls sit above full-width fields, so Stage label and Note labels remain readable.
- Guide title/content, Variety name and Service name now reject empty required input. Optional service price must be finite, numeric and non-negative, preventing invalid input from silently becoming a missing price.
- All four sheets show save failures within the sheet. Previously the three content editors used a background Scaffold snack bar that was covered by the modal; Promo saves had no caught-error presentation. Promo saves now disable the action while a request is pending and restore it after failure.
- Promo validation rejects non-finite discounts and invalid/zero/negative usage limits. Existing code/value and percentage-limit feedback is also shown inside the modal.
- Promo date picker includes existing dates outside its default window; opening an old code no longer triggers an initial-date assertion. Expiry controls and stage deletion have descriptive tooltips.
- Image-picker callbacks check that their sheet remains mounted before updating state.

## Verification

The first compact matrix reproduced **14 failures**, including both horizontal overflows, invalid empty saves and the old-expiry assertion. Follow-up failed-save tests reproduced the hidden feedback in Guide/Variety/Service; a stage-width regression reproduced the cramped inputs seen in the first visual batch.

The final focused file passes **38 tests**. The visual capture subset passes **8 scenarios** and writes **16 PNGs**. Static analysis of all four changed UI files and the focused test reports **No issues found**. Scoped `git diff --check` passes.

## Rendered acceptance

Actual widget renders are in `output/ui-final-owner/`. The initial 16 views were inspected together in light/dark contact sheets. Their two material findings—truncated selected promo label and cramped stage fields—were corrected together. A single confirmation batch was inspected; visual refinement stops here.

- `variety-light.png`, `variety-dark.png`, `variety-bottom-light.png`, `variety-bottom-dark.png`: populated edit, growth-stage controls, readable full-width input labels and Save.
- `guide-light.png`, `guide-dark.png`, `guide-bottom-light.png`, `guide-bottom-dark.png`: populated title/body and Publish. This short fixture fits without scrolling, so initial/bottom views match.
- `service-light.png`, `service-dark.png`, `service-bottom-light.png`, `service-bottom-dark.png`: populated fields, wrapped show-price/active switches, photo action and Save.
- `promo-light.png`, `promo-dark.png`, `promo-bottom-light.png`, `promo-bottom-dark.png`: complete selected discount, value/usage fields, expiry/active controls and Save.
- `contact-light.jpg`, `contact-dark.jpg`: the final 16 PNGs combined for inspection.

Captures are 320×900 at 2× text in both themes, using the installed SF face and Flutter MaterialIcons. The visual fixtures have no keyboard; keyboard clearance is covered separately by the interaction matrix. Single-line editable values intentionally scroll horizontally. Content clipped at the top of a scrolled capture is outside the scroll viewport. Photos deliberately use empty-image placeholders; no image quality acceptance is claimed.

Reproduce tests with `flutter test --no-pub test/final_owner_forms_test.dart`. On this configured macOS machine, reproduce captures with `UI_OWNER_CAPTURE=1 flutter test --no-pub test/final_owner_forms_test.dart --plain-name 'capture owner'`.

## Limits

Final async follow-up: the expanded owner suite passes **44 tests** as part of the final 389-test full run. Deferred fake saves verify safe completion after sheet dismissal for all four editors, stable variety-stage snapshots, and retaining an already-created row ID after a partial failure so retry does not create a duplicate. Provider containers and input/image snapshots are captured before asynchronous work. These are simulated saves, not production persistence acceptance.

These are widget-fixture checks, not device or production acceptance. Physical keyboards/IMEs, screen-reader traversal, OS image-picker permissions and selection, successful uploads, real remote editor-image failures, successful live saves, concurrent edits, backend authorization and persistence, deletion completion, and real owner-session navigation remain outside this evidence. List loading/error/empty coverage is inherited from the earlier page review, not newly certified by this editor-focused file. No commit, push or external mutation was performed.
