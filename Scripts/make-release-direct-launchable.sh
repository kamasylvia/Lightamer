#!/bin/zsh
# make-release-direct-launchable.sh — make a Release build direct-launchable.
#
# V2M-02 T4 (RELEASE-DIRECT-INJECT; V2-PROPOSAL section 7.2). Background:
# under the Release configuration the SPM PackageProduct frameworks
# (WebP_*/libwebp_* — Swift-WebP) are DYNAMICALLY linked by the app but stay
# in <config>/PackageFrameworks/ instead of being embedded into the bundle,
# so a direct launch dies in dyld (Debug statically inlines the same code —
# the two configurations disagree; m5-2 perf.md incident 4). The m6-closeout
# P1 batch proved the fix recipe live: copy the frameworks into
# Contents/Frameworks/ + a full ad-hoc re-sign (rc=0 probe).
#
# The script NEVER touches the production sources or the Xcode/Tuist
# configuration (zero-diff red line); it only repairs the built product on
# disk. Scripts/release/make-dmg.sh stages its copy AFTER this script runs,
# so a repaired app also produces a self-contained distribution.
#
# Usage:
#   Scripts/make-release-direct-launchable.sh [--skip-build]
#     --skip-build  repair the newest existing Release product without
#                   rebuilding (default: build Release first, ad-hoc
#                   unhardened — the make-dmg.sh signing shape)
set -euo pipefail

ROOT="${0:A:h:h}"   # Scripts/ -> repo root
cd "$ROOT"

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "== building Release (ad-hoc, unhardened — the make-dmg.sh shape) =="
  caffeinate -dis xcodebuild build \
    -workspace Lightamer.xcworkspace -scheme Lightamer \
    -configuration Release -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO \
    -quiet
  echo "build ok"
fi

# Locate the newest Release product (the make-dmg.sh container logic:
# DerivedData mtimes do not track incremental builds — pick the newest app
# binary) and its config directory (the PackageFrameworks sibling).
DD=(~/Library/Developer/Xcode/DerivedData/Lightamer-*/Build/Products/Release(N/))
if [ ${#DD[@]} -eq 0 ]; then
  echo "error: Release products directory not found — build first:" >&2
  echo "  Scripts/make-release-direct-launchable.sh" >&2
  exit 2
fi
CONFIG_DIR="${DD[1]}"
APP_CANDIDATES=("$CONFIG_DIR/Lightamer.app"(N))
if [ ${#APP_CANDIDATES[@]} -eq 0 ]; then
  echo "error: Release Lightamer.app not found in $CONFIG_DIR" >&2
  exit 2
fi
APP="$(ls -dt "${APP_CANDIDATES[@]}" | head -1)"
echo "app: $APP"

# 1) embed every PackageProduct framework that the bundle does not carry.
EMBEDDED=0
FW_SRC="$CONFIG_DIR/PackageFrameworks"
FW_DST="$APP/Contents/Frameworks"
if [ -d "$FW_SRC" ]; then
  mkdir -p "$FW_DST"
  for fw in "$FW_SRC"/*.framework(N); do
    name="${fw:t}"
    if [ -e "$FW_DST/$name" ]; then
      echo "already embedded: $name"
      continue
    fi
    ditto "$fw" "$FW_DST/$name"
    echo "embedded: $name"
    EMBEDDED=$((EMBEDDED + 1))
  done
fi
echo "embedded $EMBEDDED framework(s)"

# 2) full ad-hoc re-sign (innermost first — nested code signs before the
# bundle; `--deep` is deprecated upstream, sign the helpers explicitly).
for helper in "$APP/Contents/XPCServices"/*.xpc(N) "$APP/Contents/Frameworks"/*.framework(N) \
              "$APP/Contents/PlugIns"/*.appex(N); do
  codesign --force --sign - "$helper" >/dev/null
done
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "codesign verify ok"

# 3) direct-launch probe: the app must survive dyld (process alive) and
# present its main window. A dyld failure kills the process within ~1s.
echo "== direct-launch probe =="
open "$APP"
PROBE_PID=""
for i in {1..20}; do
  sleep 0.5
  PROBE_PID="$(pgrep -x Lightamer | head -1 || true)"
  if [ -n "$PROBE_PID" ]; then
    sleep 4   # give the UI the launch path (a dyld crash would be gone by now)
    if kill -0 "$PROBE_PID" 2>/dev/null; then
      WINS="$(osascript -e "tell application \"System Events\" to count windows of (first process whose unix id is $PROBE_PID)" 2>/dev/null || echo 0)"
      echo "probe: pid=$PROBE_PID alive, windows=$WINS"
      if [ "${WINS:-0}" -ge 1 ]; then
        echo "PROBE PASS (rc=0, main window up)"
        # leave the app running for a human smoke look; kill silently (own instance)
        kill "$PROBE_PID" 2>/dev/null || true
        exit 0
      fi
    fi
  fi
done
echo "PROBE FAIL (process did not survive or no window)" >&2
exit 1
