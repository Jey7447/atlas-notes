#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.38.0"
FLUTTER_DIR="$HOME/flutter"
FLUTTER_ARCHIVE="$HOME/flutter-sdk.tar.xz"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR" "$FLUTTER_ARCHIVE"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$FLUTTER_ARCHIVE"
  tar -xf "$FLUTTER_ARCHIVE" -C "$HOME"
  rm -f "$FLUTTER_ARCHIVE"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --enable-web
flutter pub get
flutter build web --release
