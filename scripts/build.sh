#!/usr/bin/env bash
# Builds build/Lucide Inline.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Lucide Inline"
BUNDLE_ID="com.wellguimaraes.lucide-inline"
APP="$ROOT/build/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/LucideInline"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LucideInline"
cp Resources/icons.json Resources/LUCIDE-LICENSE "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>LucideInline</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Accessibility grant across rebuilds; ad-hoc signing resets it.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)}"
codesign --force --deep --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LucideInline 2>/dev/null || true
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  open "$INSTALL_DIR/$APP_NAME.app"
  echo "Installed to $INSTALL_DIR/$APP_NAME.app"
fi
