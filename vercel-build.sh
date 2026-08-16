#!/bin/bash
set -e

# ── Install Flutter SDK (archive — much faster than git clone) ───────
# Pinned to 3.47.0 (Dart 3.13.0 — satisfies pubspec >=3.10.7 <4.0.0)
FLUTTER_VERSION="3.47.0"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

echo ">>> Downloading Flutter SDK ${FLUTTER_VERSION}..."
echo ">>> URL: ${ARCHIVE_URL}"
curl -L "$ARCHIVE_URL" -o /tmp/flutter.tar.xz
echo ">>> Download complete. Size: $(du -h /tmp/flutter.tar.xz | cut -f1)"

echo ">>> Extracting Flutter SDK..."
tar -xf /tmp/flutter.tar.xz -C /tmp/
rm -f /tmp/flutter.tar.xz
export PATH="/tmp/flutter/bin:$PATH"

echo ">>> Flutter version:"
flutter --version

echo ">>> Flutter doctor (web only):"
flutter doctor -v 2>&1 | grep -i "web\|chrome\|flutter\|dart" || true

# ── Build web ──────────────────────────────────────────────────────
echo ">>> Resolving dependencies..."
flutter pub get

echo ">>> Building Flutter web (release mode, CanvasKit renderer)..."
flutter build web --release --no-tree-shake-icons

echo ">>> Verifying build output..."
ls -la build/web/ | head -10
echo ">>> Build complete!"
