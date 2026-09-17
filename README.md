# Marugen Koi Farm

Flutter e-commerce app for Marugen Koi Farm (live fish + food/accessories).

## Backend deploy (required for payment / reviews)

```bash
# Apply migrations (0009 reviews, 0010 payment integrity, 0011 moderation)
supabase db push

# Redeploy Edge Functions after pulling these changes
supabase functions deploy create-payment-intent
supabase functions deploy stripe-webhook --no-verify-jwt
```

Checkout flow: `create-payment-intent` validates DB prices/stock, creates a
**pending** order (stock reserved), then Stripe PaymentSheet. The
`stripe-webhook` marks the order **paid**. The app never inserts a `paid`
order from the client. Fulfillment may be `delivery` or `pickup`.

### Apple Pay & Google Pay

The PaymentSheet only offers Apple Pay / Google Pay once each platform is
wired up — without this, "Pay with Stripe" falls back to card entry only
(and a redirect-based method chosen without a return URL can strand the
user outside the app).

- **Both platforms**: `Stripe.urlScheme = 'marugen'` (set in `main.dart`)
  reuses the existing `marugen://` scheme so redirect-based methods (e.g.
  PayNow, GrabPay) can return control to the app. Android already declares
  a matching `stripe-redirect` deep link in `AndroidManifest.xml`.
- **Google Pay**: no extra account setup needed — Stripe handles it. Just
  make sure `com.google.android.gms.wallet.api.enabled` stays in
  `AndroidManifest.xml` (already added).
- **Apple Pay**:
  1. Apple Developer → Identifiers → **Merchant IDs** → create one, e.g.
     `merchant.com.marugen.marugenApp`.
  2. Xcode → Runner target → **Signing & Capabilities** → **+ Capability**
     → **Apple Pay** → select that merchant ID (this writes the
     `com.apple.developer.in-app-payments` entitlement into
     `Runner.entitlements`).
  3. Set the same ID in the app's `.env` as `APPLE_MERCHANT_ID` (and
     optionally in `ios/Flutter/Secrets.xcconfig` if you'd rather keep the
     entitlement templated via `$(APPLE_MERCHANT_ID)` instead of the
     literal value Xcode writes).
  4. Register the same merchant ID in the Stripe Dashboard → Settings →
     **Apple Pay**.

  Leaving `APPLE_MERCHANT_ID` unset just disables the Apple Pay button —
  it does not affect card payments.

## Google & Apple Sign-In

Native ID-token flows (no browser) for iOS.

### Google

1. [Google Cloud Console](https://console.cloud.google.com/) → create OAuth clients:
   - **Web** application (Client ID + secret)
   - **iOS** application (bundle ID `com.marugen.marugenApp`)
2. Supabase → **Authentication → Providers → Google** → enable → paste Web Client ID + secret.
3. App `.env`:
   ```
   GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com
   GOOGLE_IOS_CLIENT_ID=....apps.googleusercontent.com
   ```
4. iOS secrets (URL scheme for Google SDK):
   ```bash
   cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
   ```
   Set `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID`
   (`com.googleusercontent.apps.` + the part before `.apps.googleusercontent.com`).

### Apple

1. Apple Developer → App ID `com.marugen.marugenApp` → enable **Sign in with Apple**.
2. Supabase → **Authentication → Providers → Apple** → enable → add Client ID
   `com.marugen.marugenApp` (bundle ID).
3. Xcode already uses `Runner/Runner.entitlements` for the capability.
