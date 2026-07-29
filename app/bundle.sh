#!/usr/bin/env bash
# Build KeyDeck.app — a self-contained, double-clickable macOS app.
#
# There is nothing else to install: the engine is compiled into this binary, so
# the app IS the product. Output: app/KeyDeck.app
set -euo pipefail
cd "$(dirname "$0")"   # app/

CONFIG="${1:-release}"   # release | debug
echo "Building KeyDeck ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/KeyDeck"
[ -f "$BIN" ] || { echo "error: $BIN not found" >&2; exit 1; }

APP="KeyDeck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeyDeck"

# LSUIElement: KeyDeck lives in the menu bar. It has a settings window, but the
# window is a visitor — closing it must not stop your shortcuts working.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>KeyDeck</string>
    <key>CFBundleDisplayName</key>     <string>KeyDeck</string>
    <key>CFBundleIdentifier</key>      <string>com.arturgrochau.keydeck</string>
    <key>CFBundleExecutable</key>      <string>KeyDeck</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>2.0.0</string>
    <key>CFBundleShortVersionString</key><string>2.0.0</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS lets it launch locally.
#
# Accessibility permission is remembered per code identity, and an ad-hoc
# signature changes on every rebuild — so during development macOS may ask again
# after a rebuild. Signing with a real Developer ID certificate (and notarizing
# for distribution) makes the grant stick; see the README release checklist.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $PWD/$APP"
echo "Run it with:  open $APP"
