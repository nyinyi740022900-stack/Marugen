# Final customer flow review — 23 October 2026

This follow-up closes the startup and secondary customer surface gaps identified in `ui-page-review-2026-10-23.md`. It preserves Marugen's existing theme, product copy, purchase behavior and account rules. Evidence is from actual Flutter widget renders and fixture interactions; no live account or external service was changed.

## Fixed defects

- **Setup required:** the instruction column overflowed by 515 logical pixels at 320×300 with 2× text. Its existing content now scrolls.
- **Profile logout confirmation:** the existing dialog overflowed by 192 pixels at 320×480 with 2× text. Its content now scrolls; cancelling returns safely to the profile. Only `confirmLogout` was changed in the shared dialog file.
- **Address error recovery:** at 320×640 with 2× text, the Add Address floating button covered Retry. A regression tap hit Add Address and the failed request was never retried. Error and empty content now reserve bottom space; the test reaches Retry, loads the saved address, opens its edit sheet and validates a missing required name.
- **Auth validation:** the rendered login, signup and reset-password forms truncated “Minimum 6/8 characters” into an ellipsis. Auth field error text now allows wrapping. Regression assertions inspect the rendered password requirement for truncation. Validation rules and text are unchanged.
- **Signup terms:** the consent `RichText` did not follow the user's text scale and did not inherit the app font. It now uses the current text scaler and existing body style, preserving the terms/privacy wording and links. A 2× regression checks the scaler.
- **Unknown route:** the existing “Route not found” text now has a Back to Shop action inside a safe, scrollable surface. A fixture router verifies a long invalid URL can recover without navigation history. Production routing uses this screen through its error builder; auth/role redirects are unchanged.

## Runtime coverage

`test/final_customer_flows_test.dart` contains 40 scenarios: the original 28 presentation checks split across light and dark `AppTheme` at 320 logical pixels wide and 2× text:

- Splash rendering at 320×300, including actual bundled logo in the captures. Real session restoration and OS launch transition are separate integration checks.
- Missing-configuration instructions at 320×300, with system brightness and text scale.
- Long unknown URL wrapping and working Back to Shop navigation.
- Login, signup, forgot-password and reset-password invalid fields with a 250-pixel simulated keyboard inset at 320×640; focus opens the test keyboard, complete password requirements render, and primary actions can be scrolled into the visible area above the inset.
- Forgot-password fake request failure, retry, success message, and Back to Login returning to the prior page. No reset email is sent.
- Profile notification-setting fake failure restoring the switch and displaying the existing recovery message.
- Logout confirmation opening and cancellation at 320×480; no sign-out call is made.
- Address failed read and Retry, populated/default card, edit sheet and required-field validation; delete confirmation with a long address label and safe cancellation. No save or delete request is sent.
- Notification failed read and Retry followed by a fixture unread inbox and Mark all read. The notifier is fake; this proves UI wiring rather than persisted read state.
- Wishlist failed read and Retry returning an empty fixture. Existing removal/rollback coverage remains in `ux_review_regressions_test.dart`.

The review exercises native Flutter focus, labeled controls such as Delete address/Mark all read, and hit testing. It does not establish VoiceOver/TalkBack reading order or real OS keyboard/permission behavior.

## Rendered evidence

`output/ui-final-customer/` contains 28 actual rendered PNGs, plus four contact sheets. All capture contexts use 320-pixel width and 2× text in each theme. Heights are 640 except startup/setup (300) and logout (480). Auth form captures show focused invalid fields above a simulated 250-pixel keyboard inset; the blank lower area is the inset, not a rendered system keyboard. Screenshots are scrolled states, not full-page images.

File pairs, each with `-light.png` and `-dark.png`:

- `splash`, `setup`, `unknown-route`
- `LoginScreen`, `SignupScreen`, `ForgotPasswordScreen`, `ResetPasswordScreen`
- `reset-success`, `logout`
- `address-error`, `address-edit`, `address-delete`
- `notifications`, `wishlist-error`

One batched visual inspection found the password-error/terms issues. One confirmation batch verified the full requirement wrapping, scalable readable terms and bundled splash logo. The initial capture harness needed its image encoding moved into real async execution before producing images; that failed harness attempt produced no visual acceptance evidence. Fonts are loaded from installed SF Pro Text and Flutter's MaterialIcons only when `UI_CUSTOMER_CAPTURE=1`; ordinary tests remain portable. No production typography override is applied by the capture harness.

Reproduce captures on this configured macOS host with `UI_CUSTOMER_CAPTURE=1 flutter test --no-pub test/final_customer_flows_test.dart`.

## Verification and limits

The expanded dedicated 40-test suite and the earlier 28-test screenshot confirmation passed. Static analysis of the ten scoped files reported no issues; formatting and whitespace checks passed. The final combined five-file customer regression suite passed **79 tests** (`final_customer_flows_test`, `forms_responsive_test`, `recovery_layout_test`, `theme_preference_test`, and `guest_account_consistency_test`), including the twelve additional async tests below. The final complete app suite passes 389 tests.

External acceptance still required: real Google/Apple/email sign-in and registration; confirmation/recovery deep links and temporary sessions; successful password update; cold-start auth/profile fetch timing; notification receipt, OS permission prompts and badge writes; avatar picker/upload; successful logout and account deletion; address create/update/default/delete persistence; wishlist sync and notification read persistence. Existing account deletion/payment behavior was not exercised. Native Android/iOS checks belong to the parent task. This report does not claim live backend or screen-reader sign-off.


## Final async auth review

Deferred fake requests reproduced two additional defects after the visual pass: login/signup could update disposed state after Back, and all four auth/recovery forms could send a second request if the user refocused the field and pressed keyboard Done while the first request was pending. Each form now ignores an in-flight submission; login/signup also prevent concurrent email and OAuth starts and check `mounted` before success/error state updates. Existing validation, provider calls, copy and layout are preserved.

Twelve additional widget tests cover repeated IME submissions across login/signup/forgot/reset and login/signup request completion after Back for success/failure with email and Google fake requests. These checks use no SDK providers or live authentication. The original red run sent two requests instead of one in all four forms and produced five setState-after-dispose failures. The fixed 40-test file passes. No additional visual pass was needed for these nonvisual guards.
