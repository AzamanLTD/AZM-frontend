#!/bin/bash
set -e

echo ">>> Fetching pre-built web app from gh-pages branch..."
git fetch origin gh-pages:gh-pages 2>/dev/null || true

# Checkout the pre-built files from gh-pages into the output directory
mkdir -p build/web
git archive gh-pages | tar -x -C build/web

echo ">>> Pre-built files ready"
ls -la build/web/ | head -10
echo ">>> Deploy complete!"
