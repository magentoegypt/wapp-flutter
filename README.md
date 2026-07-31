# clickalize

Clickalize — WhatsApp Business vendor console for mobile.

## Running it

```bash
flutter run -t lib/main_dev.dart --dart-define-from-file=config/dev.json
```

Flavors are `dev`, `staging` and `prod` — each pairs `lib/main_<flavor>.dart` with
`config/<flavor>.json`.

## Shipping it

Two GitHub Actions pipelines, both publishing to [Loadly](https://loadly.io):

- [**Android**](docs/ci-loadly.md) — builds and verifies on every push to `main`; publishes a
  signed APK on demand or on a `v*` tag.
- [**iOS (Ad Hoc)**](docs/ci-loadly-ios.md) — builds a signed `.ipa` on demand or on a `v*`
  tag. Ad Hoc installs only on devices registered in the provisioning profile.

Each doc covers the one-time credential setup its pipeline needs. A `v*` tag runs both.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
