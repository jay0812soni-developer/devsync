#!/bin/bash
set -e

echo "=========================================="
echo " DevSync - Vercel Flutter Web Build"
echo "=========================================="

FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Downloading Flutter stable channel..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
else
  echo "Using cached Flutter SDK..."
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo "Flutter version:"
flutter --version
flutter config --no-analytics

echo "Resolving dependencies..."
flutter pub get

echo "Building web release bundle..."
flutter build web --release --no-wasm-dry-run

echo "Build complete! Output in build/web"
