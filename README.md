# Azaman Flutter Mobile App

Flutter mobile application for the Azaman P2P crypto exchange and social-finance platform.

> **Mobile-only repository:** Android and iOS are the supported application targets. The separate web application is maintained in its own repository.

## Stack

- **Language**: Dart (SDK `>=3.10.7 <4.0.0`)
- **State management**: Riverpod 2.6 (sole state layer — no `provider` package)
- **Navigation**: go_router 14
- **Real-time**: socket_io_client 3.1 (single unified connection)
- **Push notifications**: Firebase Messaging + flutter_local_notifications
- **Crash reporting**: Sentry Flutter (inactive unless `SENTRY_DSN` dart-define is set)
- **Auth storage**: flutter_secure_storage (JWT)

## Getting Started

```bash
flutter pub get
flutter run
```

### Build-time configuration

Environment-sensitive values are passed via `--dart-define`:

```bash
# Development — defaults to localhost:3000
flutter run --dart-define=ENV=dev

# Staging
flutter run --dart-define=ENV=staging

# Production
flutter run --dart-define=ENV=prod

# Override API host (for example, a backend running on your LAN)
flutter run --dart-define=API_HOST=192.168.1.100 --dart-define=API_PORT=3000

# Enable Sentry crash reporting
flutter run --dart-define=SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz
```

For a physical device or emulator, use an appropriate `API_HOST` when developing against a backend running on your local machine.

## Architecture

- **Single socket**: `SocketService` owns the single authenticated Socket.IO connection. All socket events (balance updates, trade updates, AZM rewards, notifications) are routed through it.
- **Granular Riverpod**: `.select(...)` on provider watches to prevent unnecessary widget-tree rebuilds. Live oracle rates repaint only the widgets that consume them.
- **Financial safety**: Destructive financial actions are protected by `SlideToConfirm`, with biometric pre-gating where enabled.
- **Biometric gate**: Users can enable biometric protection for financial actions in Security Settings.
- **Connectivity banner**: `AzamanConnectivityBanner` shows an offline strip immediately when network connectivity is lost and confirms recovery when it returns.

## Supported Platforms

| Platform | Status |
|---|---|
| Android | Supported |
| iOS | Supported |
| Web | Maintained in separate repository |

## Key Screens

| Screen | Path |
|---|---|
| Home (hologram balance + live market) | `/` |
| P2P Marketplace | `/marketplace` |
| Active Trade | `/trade/:id` |
| Friends Hub (DMs, transfers, tickets) | `/friends` |
| Savings Goals | `/savings` |
| AZM Rewards | `/azm-rewards` |
| Vendor Dashboard | (drawer → vendor section) |
| Notification Hub | `/notifications` |
| Security Settings (2FA, PIN, biometric) | `/security` |
| KYC Verification | (settings → verify identity) |

## Sentry (F-05)

Sentry is disabled by default. Pass `--dart-define=SENTRY_DSN=<dsn>` at build time to enable it. The app bootstraps inside `SentryFlutter.init` only when the DSN is non-empty.
