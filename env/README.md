# Environment separation (dev vs prod)

By default this app reads Supabase/Stripe/Google keys from `.env` at the
repo root (see `.env.example`) — the same file for every build, manually
swapped. That's fine for solo local development, but risks a release build
accidentally pointing at the wrong backend (e.g. shipping to Play Store
with a dev/test Supabase project still in `.env`).

To point a build at a specific, separate environment instead, without
touching `.env` at all:

```bash
# One-time: copy the template and fill in your real production values.
cp env/prod.json.example env/prod.json   # gitignored — never commit real keys

# Any build/run that should use prod:
flutter build appbundle --release --dart-define-from-file=env/prod.json
flutter run --dart-define-from-file=env/prod.json
```

Values from `--dart-define-from-file` always win over `.env` (see
`lib/core/config/env.dart`) — they are baked in at compile time. The `.env` file is still bundled
because it is listed in `pubspec.yaml`; overrides do not remove that
asset. Before release, ensure `.env` contains only the intended public
client configuration (or placeholders). Never put Stripe secret keys,
Supabase service-role keys, or other server secrets in `.env` or Dart defines.

If a **release** build is ever run without `APP_ENV=prod` set this way,
the app shows an unmissable red "NON-PROD BACKEND — RELEASE BUILD" banner
at the top of the screen (release builds only; `--dart-define=APP_ENV=dev`
during a debug `flutter run` for a Play Store build is what you'd
intentionally use for a staging/internal-testing track). Never ship a
build with that banner showing to the production Play Store track.

You'll need a genuinely separate Firebase project (for a separate
`google-services.json` / `GoogleService-Info.plist`) if you want dev push
notifications/Crashlytics to stay fully isolated from prod too — that part
isn't handled by this file and needs its own Firebase project setup.

## Closed beta production configuration

The Alpha track is a distribution channel, not a separate backend. If it uses the existing production Supabase project, build it with the same reviewed production client configuration:

```sh
flutter test --dart-define-from-file=env/prod.json
flutter build appbundle --release --dart-define-from-file=env/prod.json --build-name=1.0.8 --build-number=13
```

Run Flutter tests and the Android release build sequentially: test tooling can regenerate the Android plugin registrant. An unqualified release build defaults APP_ENV to dev and uses the bundled .env values, which currently contain a Stripe test publishable key. Do not hide the release warning independently or set only APP_ENV=prod: verify the backend and the Stripe publishable-key mode together. Keep private keys server-side.

A production-configured closed beta uses real Stripe payments. Automated tests do not establish successful physical-device payment acceptance.
