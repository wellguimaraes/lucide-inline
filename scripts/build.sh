#!/usr/bin/env bash
# Builds build/Lucide Inline.app. Pass --install to copy it to /Applications and launch it.
#
# Env:
#   VERSION        CFBundleShortVersionString (default 1.0.0)
#   UNIVERSAL=1    build arm64 + x86_64 (default: this Mac's arch only)
#   SIGN_IDENTITY  codesign identity (default: first "Apple Development" identity, else ad-hoc)
#   SIGN_KEYCHAIN  keychain holding SIGN_IDENTITY, if not in the search list
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Lucide Inline"
BUNDLE_ID="com.wellguimaraes.lucide-inline"
APP="$ROOT/build/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
VERSION="${VERSION:-1.0.0}"

ARCH_ARGS=()
[[ "${UNIVERSAL:-}" == "1" ]] && ARCH_ARGS=(--arch arm64 --arch x86_64)

cd "$ROOT"
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)/LucideInline"

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A stable signing identity keeps the Accessibility grant across rebuilds; ad-hoc signing resets it.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)}"
SIGN_ARGS=(--force --options runtime --sign "${IDENTITY:--}")
[[ -n "$IDENTITY" ]] && SIGN_ARGS+=(--timestamp)
[[ -n "${SIGN_KEYCHAIN:-}" ]] && SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
codesign "${SIGN_ARGS[@]}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LucideInline 2>/dev/null || true
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  open "$INSTALL_DIR/$APP_NAME.app"
  echo "Installed to $INSTALL_DIR/$APP_NAME.app"
fi
