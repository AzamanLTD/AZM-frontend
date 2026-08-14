#!/bin/bash
set -e

# ── Install Flutter SDK (stable channel) ────────────────────────────
echo ">>> Downloading Flutter SDK..."
git clone --depth 1 -b stable https://github.com/flutter/flutter.git /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"

echo ">>> Flutter version:"
flutter --version

# ── Build web ──────────────────────────────────────────────────────
echo ">>> Resolving dependencies..."
flutter pub get

echo ">>> Building Flutter web..."
flutter build web --release

echo ">>> Build complete!"
