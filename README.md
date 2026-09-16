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
