# Closed beta 1.0.10 (15): automatic option names and support content

User approved kg-derived option names with editable overrides, requested no live-animal sales wording in FAQ/Terms/Privacy, and removal of the red Terms placeholder.

## Changes

Variant kg input generates 0.5 → 500g, 2 → 2kg and 1.25 → 1.25kg. Generated labels follow subsequent weight changes. Manual labels such as 500ml are preserved; clearing the label restores automatic naming on the next kg edit. Product and variant weights and the server shipping calculation remain unchanged. Labels remain editable.

FAQ and Terms now use generic product support and delivery wording. Removed the live-arrival guarantee and red demonstration disclaimer, without claiming legal review or platform-policy approval. Privacy already contains no live-animal sales section; its actual data-handling disclosures remain intact. The local public Terms HTML was updated consistently; it has not been separately deployed to public website hosting. Actual catalogue/functionality is unchanged.

Dimensions remain optional for the current weight-based quotation flow; dimensions can affect courier volumetric pricing. No blanket fabricated parcel size was introduced.

## Verification

Regression first observed empty label instead of 500g; after implementation the variant UI test passed and preserved custom 500ml labels. Focused variant/forms/privacy suite: 27 passed. Full production-configured suite: 245 passed. Analysis: no issues. Terms preview inspected at output/terms-updated.png. No physical-device login, real payment or carrier booking was performed.

Signed release artifact built and verified: output/releases/marugen-1.0.10-15-auto-label.aab, SHA-256 03e2e65d5c447e8c48670413f6a7be272512e8b7a1dc5f053b88e8b5caf5c174. Production configuration verified in all native architecture binaries; signature jar verified. Play submission is in progress. Previous Alpha 1.0.9 (14) was observed Published / available to selected testers on October 20. Existing Alpha tester settings and production release track must remain unchanged.

## Play submission status

The chooser eventually enabled Open and upload completed from the verified original artifact. Play validated version 15 (1.0.10), release notes were confirmed, and the Preview and confirm screen reported Ready to release with 100% Alpha rollout.

Review submission remains unverified. After the user reopened Chrome, repeated Save attempts returned unchanged accessibility state. Native interaction also reported elementHasNoFrame / noWindowsAvailable, inventory timed out, and screenshot content disagreed with the accessibility tree. Rebinding Chrome and a normal page refresh did not restore reliable interaction. Do not claim Changes in review or upload another bundle. Resume the existing release 15, save it, and submit the single Alpha change from Publishing overview, then verify Changes in review.
