#!/usr/bin/env bash
# Verify KeyDeck: build the app, then run the core + engine logic assertions. The assertions run WITHOUT XCTest (which ships only with full Xcode),
# so this works on Command Line Tools alone. If XCTest is available, `swift test`
# is run too.
set -euo pipefail
cd "$(dirname "$0")/.."   # app/

echo "== 1. swift build (KeyDeckCore + KeyDeckEngine + the app) =="
swift build

echo "== 2. core + engine logic assertions (no XCTest needed) =="
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TGT="arm64-apple-macosx13.0"
OUT="$(mktemp -d)/kd_checks"
# The checks compile Core + Engine + the runner as ONE module, so the
# cross-module imports have to be stripped from the copies we feed swiftc.
SRC="$(mktemp -d)/src"
mkdir -p "$SRC"
cp Sources/KeyDeckCore/*.swift Sources/KeyDeckEngine/*.swift test/checks/main.swift "$SRC/"
sed -i '' -e '/^import KeyDeckCore$/d' -e '/^import KeyDeckEngine$/d' "$SRC"/*.swift
xcrun swiftc -sdk "$SDK" -target "$TGT" "$SRC"/*.swift -o "$OUT"
"$OUT"

echo "== 3. swift test (XCTest; requires full Xcode) =="
if swift test 2>/tmp/kd_swifttest.log; then
  echo "  swift test passed"
else
  if grep -q "no such module 'XCTest'" /tmp/kd_swifttest.log; then
    echo "  skipped: XCTest unavailable (Command Line Tools only — install Xcode to run)"
  else
    echo "  swift test FAILED:"; tail -20 /tmp/kd_swifttest.log; exit 1
  fi
fi

echo "== APP CHECKS PASSED =="
