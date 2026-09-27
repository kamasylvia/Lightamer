#!/bin/zsh
# make-dmg.sh — build the distribution artifacts: DMG + zip + SHA256SUMS.
#
# Plan 13-4 (2026-09-27 ruling): GitHub-only distribution, UNSIGNED —
# no Developer ID signing, no notarization (the Apple channel was cut).
# Downloads carry no quarantine-breaking signature; users bypass
# Gatekeeper themselves (right-click > Open).
#
# Layout: drag-install DMG (app + /Applications symlink), UDZO
# compressed, plus a plain zip for unarchiver users. Version comes from
# the built app's Info.plist (MARKETING_VERSION in Project.swift).
#
# Usage:
#   Scripts/release/make-dmg.sh            # builds the Release app itself
#
# Signing: ad-hoc ("-") with hardened runtime OFF — the unsigned
# distribution shape (Developer ID + hardened was cut with the Apple
# channel). Hardened + a no-Team-ID self-signed cert trips dyld
# library validation on macOS 27 ("different Team IDs" at load), and
# hardened buys nothing without notarization.
set -euo pipefail

ROOT="${0:A:h:h:h}"   # zsh: repo root (Scripts/release/ -> root)
cd "$ROOT"

echo "== building Release (ad-hoc, unhardened) =="
caffeinate -dis xcodebuild build \
  -workspace Lightamer.xcworkspace -scheme Lightamer \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO \
  -quiet
echo "build ok"

# Locate the newest Release product (same container logic as
# test-direct.sh: DerivedData dir mtimes do not track incremental
# builds, so pick the newest app binary).
DD_DEFAULT=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Release/Lightamer.app(N))
if [ ${#DD_DEFAULT[@]} -eq 0 ]; then
  echo "error: Release Lightamer.app not found — build first:" >&2
  echo "  xcodebuild build -workspace Lightamer.xcworkspace -scheme Lightamer \\" >&2
  echo "    -configuration Release -destination 'platform=macOS'" >&2
  exit 2
fi
APP="$(ls -dt "${DD_DEFAULT[@]}" | head -1)"
echo "app: $APP"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
OUT="$ROOT/build/release"
mkdir -p "$OUT"
DMG="$OUT/Lightamer-$VERSION.dmg"
ZIP="$OUT/Lightamer-$VERSION.zip"

# 1) staging: app + Applications symlink (drag-install layout)
STAGING="$(mktemp -d /tmp/lightamer-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Lightamer.app"
ln -s /Applications "$STAGING/Applications"

# 2) DMG (UDZO compressed, plain volume — no custom backdrop)
hdiutil create -volname "Lightamer $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" | tail -1

# 3) zip (ditto keeps resource forks / symlink structure)
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 4) checksums
(
  cd "$OUT"
  shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt
  cat SHA256SUMS.txt
)

echo "artifacts in $OUT:"
ls -lh "$OUT"
