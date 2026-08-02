# Azaman Flutter App

Flutter mobile application for the Azaman P2P crypto exchange platform.

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

All environment-sensitive values are passed via `--dart-define`:

```bash
# Target a specific environment
flutter run --dart-define=ENV=dev        # default — connects to live Render backend
flutter run --dart-define=ENV=staging
flutter run --dart-define=ENV=prod

# Override API host (e.g. local backend on LAN)
flutter run --dart-define=API_HOST=192.168.1.100 --dart-define=API_PORT=3000

# Enable Sentry crash reporting
flutter run --dart-define=SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz
```

Defaults to the live deployed backend (`https://azm-backend.onrender.com`) so iOS Simulator and Android Emulator work out-of-the-box with no extra config.

## Architecture

- **Single socket**: `SocketService` owns the single authenticated Socket.IO connection. All socket events (balance updates, trade updates, AZM rewards, notifications) are routed through it.
- **Granular Riverpod**: `.select(...)` on every provider watch to prevent full-tree rebuilds. Streams like live oracle rates repaint only their specific text widget.
- **Financial safety**: Every destructive financial action (withdrawal, P2P trade, savings fund/withdraw, peer transfer) is behind a `SlideToConfirm` widget, with an optional biometric pre-gate.
- **Biometric gate**: Users can enable "Biometric Lock on financial actions" in Security Settings — gated in both directions so the setting itself requires biometric to change.
- **Connectivity banner**: `AzamanConnectivityBanner` overlays every screen and shows an offline strip when the device loses network, with a reconnected flash on recovery.

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

Sentry is disabled by default. Pass `--dart-define=SENTRY_DSN=<dsn>` at build time to enable it. The app bootstraps inside `SentryFlutter.init` only when the DSN is non-empty, so CI/dev builds produce no network calls to Sentry.
