#!/bin/bash
set -e

# ── Install Flutter SDK ─────────────────────────────────────────────
FLUTTER_VERSION="3.47.0"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

echo ">>> Downloading Flutter SDK ${FLUTTER_VERSION}..."
curl -L --progress-bar "$ARCHIVE_URL" -o /tmp/flutter.tar.xz

echo ">>> Extracting..."
tar -xf /tmp/flutter.tar.xz -C /tmp/
rm -f /tmp/flutter.tar.xz
export PATH="/tmp/flutter/bin:$PATH"

echo ">>> Flutter version:"
flutter --version

# ── Build web ──────────────────────────────────────────────────────
echo ">>> Resolving dependencies..."
flutter pub get

echo ">>> Building Flutter web..."
flutter build web --release --no-tree-shake-icons

echo ">>> Build output:"
ls -la build/web/
echo ">>> Build complete!"
