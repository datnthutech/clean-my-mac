#!/usr/bin/env bash
# Builds Clean My Mac end to end on a Mac: tools → project → tests → universal Release app → DMG.
#
#   scripts/build.sh            # full build, output in build/
#   SKIP_TESTS=1 scripts/build.sh
#
# Optional notarization (needs a paid Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="notary-profile" scripts/build.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP_NAME="CleanMyMac"
DISPLAY_NAME="Clean My Mac"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

step() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31merror:\033[0m %s\n" "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "This script must run on macOS (Xcode is required)."
xcode-select -p >/dev/null 2>&1 || fail "Xcode command line tools not found. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"

step "Checking tools"
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    fail "XcodeGen is missing. Install Homebrew (https://brew.sh) then run: brew install xcodegen"
  fi
fi
xcodebuild -version

step "Checking localization"
python3 scripts/check_localization.py

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  step "Running DiskKit unit tests"
  swift test --package-path Packages/DiskKit
fi

step "Generating Xcode project"
xcodegen generate --quiet

step "Building universal Release app (arm64 + x86_64)"
rm -rf "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build | { command -v xcpretty >/dev/null && xcpretty || cat; }

APP="$BUILD_DIR/$DISPLAY_NAME.app"
rm -rf "$APP"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$APP"

step "Signing ($SIGN_IDENTITY)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

step "Creating DMG"
"$ROOT/scripts/make_dmg.sh" "$APP"

if [[ -n "${NOTARY_PROFILE:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  step "Notarizing"
  DMG="$(ls -t "$BUILD_DIR"/*.dmg | head -1)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

step "Done"
ls -lh "$BUILD_DIR"/*.dmg
echo "App: $APP"
