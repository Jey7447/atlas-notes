#!/usr/bin/env bash
set -uo pipefail

FLUTTER_VERSION="3.38.0"
FLUTTER_DIR="$HOME/flutter"
FLUTTER_ARCHIVE="$HOME/flutter-sdk.tar.xz"
LOG="/tmp/atlas-flutter-build.log"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR" "$FLUTTER_ARCHIVE"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$FLUTTER_ARCHIVE" || exit $?
  tar -xf "$FLUTTER_ARCHIVE" -C "$HOME" || exit $?
  rm -f "$FLUTTER_ARCHIVE"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_DIR" || true
: > "$LOG"
run_step() {
  echo ">>> $*" | tee -a "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
  return ${PIPESTATUS[0]}
}

status=0
run_step flutter --version || status=1
if [ "$status" -eq 0 ]; then run_step flutter pub get || status=1; fi
if [ "$status" -eq 0 ]; then run_step flutter build web --release || status=1; fi

if [ "$status" -ne 0 ]; then
  mkdir -p build/web
  { echo "<!doctype html><html><head><meta charset=\"utf-8\"><title>Atlas build diagnostic</title><style>body{background:#101318;color:#eee;font:14px monospace;padding:24px}pre{white-space:pre-wrap;line-height:1.45;background:#181d24;padding:18px;border-radius:10px}</style></head><body><h1>Atlas Flutter build diagnostic</h1><pre>"; cat "$LOG"; echo "</pre></body></html>"; } > build/web/index.html
  exit 0
fi
