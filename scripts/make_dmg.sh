#!/usr/bin/env bash
# Packs an .app into a compressed DMG with an /Applications shortcut.
#   scripts/make_dmg.sh "build/Clean My Mac.app"
set -euo pipefail

APP="${1:?usage: make_dmg.sh <path to .app>}"
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="$(basename "$APP" .app)"
DMG="$ROOT/build/CleanMyMac-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Created $DMG"
