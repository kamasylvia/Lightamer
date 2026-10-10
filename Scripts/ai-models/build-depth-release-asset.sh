#!/bin/zsh
# build-depth-release-asset.sh — assemble the depth-anything-v2-small-f16
# GitHub Release asset end to end (plan M4-3-01 KD-1).
#
# Unlike build_default_bundle.sh (conversion pipeline), the depth profile
# is a ZERO-CONVERSION direct fetch: Apple's official Core ML F16
# conversion on Hugging Face IS the release unit (ruling OQ-1/D-5). The
# chain here: download (HF pinned revision, hf-mirror fallback) → verify
# → assemble the distribution zip (mlpackage + LICENSE + NOTICE +
# MANIFEST.sha256) → SELF-CHECK the zip content list (checker m4: a
# missing co-shipped piece exits non-zero) → rewrite the
# `depthAnythingV2SmallF16` sentinel in ModelAssetDigests.generated.swift.
#
# Model bytes NEVER enter the repo: everything lands under
# ~/Library/Caches/LightamerModels/depth/ (outside git; the .gitignore
# Resources/AIModels red line is untouched).
#
# Usage: Scripts/ai-models/build-depth-release-asset.sh
#
# The digest this script publishes is the SHA-256 lock over the FINAL
# distribution bytes (the zip). Release upload (gh release upload
# ai-models-v1 <zip>) is the T8 ops step; digest-before-upload is safe
# (fail-closed: an unpublished asset downloads to a typed allSourcesFailed).

set -euo pipefail

ROOT="${0:A:h:h:h}"                       # repo root
CACHE="$HOME/Library/Caches/LightamerModels/depth"
RELEASE_DIR="$CACHE/release"
ZIP_PATH="$CACHE/depth-anything-v2-small-f16.mlpackage.zip"
DIGESTS_SWIFT="$ROOT/LightamerCore/Sources/AI/ModelAssetDigests.generated.swift"

REPO="apple/coreml-depth-anything-v2-small"
REVISION="cfef6f6f2a70783dedc0bfae40cecbc2052285d3"
PKG_NAME="depth-anything-v2-small-f16.mlpackage"
UPSTREAM_PKG="DepthAnythingV2SmallF16.mlpackage"
SENTINEL="depthAnythingV2SmallF16"
LICENSE_URL="https://www.apache.org/licenses/LICENSE-2.0.txt"

mkdir -p "$CACHE" "$RELEASE_DIR"

fetch() {  # fetch <relative-path> <dest>
  local rel="$1" dest="$2"
  curl -fsSL --max-time 300 -o "$dest" \
    "https://huggingface.co/$REPO/resolve/$REVISION/$rel" \
  || curl -fsSL --max-time 300 -o "$dest" \
    "https://hf-mirror.com/$REPO/resolve/$REVISION/$rel"
}

# ── 1. Download (pinned revision; idempotent) ────────────────────────────
echo "==> download $UPSTREAM_PKG (revision $REVISION)"
TMP_DL="$CACHE/.download"
rm -rf "$TMP_DL"; mkdir -p "$TMP_DL/$UPSTREAM_PKG/Data/com.apple.CoreML/weights"
fetch "$UPSTREAM_PKG/Data/com.apple.CoreML/model.mlmodel" \
  "$TMP_DL/$UPSTREAM_PKG/Data/com.apple.CoreML/model.mlmodel"
fetch "$UPSTREAM_PKG/Data/com.apple.CoreML/weights/weight.bin" \
  "$TMP_DL/$UPSTREAM_PKG/Data/com.apple.CoreML/weights/weight.bin"
fetch "$UPSTREAM_PKG/Manifest.json" \
  "$TMP_DL/$UPSTREAM_PKG/Manifest.json"

WEIGHT_BYTES=$(stat -f%z "$TMP_DL/$UPSTREAM_PKG/Data/com.apple.CoreML/weights/weight.bin")
if (( WEIGHT_BYTES < 45000000 || WEIGHT_BYTES > 55000000 )); then
  echo "!! weight.bin is $WEIGHT_BYTES bytes — outside the 45-55 MB sanity" \
       "band (truncated download?)" >&2
  exit 1
fi

# ── 2. Assemble the distribution tree (renamed package + co-shipped) ─────
echo "==> assemble $RELEASE_DIR"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
mv "$TMP_DL/$UPSTREAM_PKG" "$RELEASE_DIR/$PKG_NAME"
rm -rf "$TMP_DL"

if [[ ! -s "$CACHE/apache-2.0.txt" ]]; then
  curl -fsSL --max-time 60 -o "$CACHE/apache-2.0.txt" "$LICENSE_URL"
fi
grep -q "Version 2.0, January 2004" "$CACHE/apache-2.0.txt" \
  || { echo "!! LICENSE fetch does not look like Apache-2.0" >&2; exit 1; }
cp "$CACHE/apache-2.0.txt" "$RELEASE_DIR/LICENSE"

cat > "$RELEASE_DIR/NOTICE" <<'EOF'
Lightamer — depth mask model asset notice
=========================================

This archive ships a Core ML conversion of Depth Anything V2 Small.

1. Depth Anything V2 Small weights
   Copyright 2024 The Depth Anything authors (HKU + TikTok).
   License: Apache-2.0
   https://github.com/DepthAnything/Depth-Anything-V2
   https://huggingface.co/depth-anything/Depth-Anything-V2-Small-hf

2. Core ML conversion
   Copyright 2024 Apple Inc.
   License: Apache-2.0
   https://huggingface.co/apple/coreml-depth-anything-v2-small

Both upstream works are licensed under the Apache License 2.0 (see the
accompanying LICENSE file). This archive is redistributed as part of the
Lightamer project solely under the terms of that license.
EOF

# MANIFEST.sha256 — the content list of EVERYTHING in the zip (the M3-3
# five-piece precedent form: "<sha256>  <relpath>").
( cd "$RELEASE_DIR" && find . -type f ! -name MANIFEST.sha256 \
    | sed 's|^\./||' | LC_ALL=C sort \
    | while read -r f; do print -r -- "$(shasum -a 256 "$f" | cut -d' ' -f1)  $f"; done \
) > "$RELEASE_DIR/MANIFEST.sha256"

# ── 3. Zip (the distribution unit). DETERMINISTIC: fixed mtimes + no
#       extra fields (-X) + sorted entry order — two builds of the same
#       revision must produce byte-identical archives, or the published
#       digest would not survive a rebuild. ────────────────────────────────
echo "==> zip $ZIP_PATH"
rm -f "$ZIP_PATH"
find "$RELEASE_DIR" -type f -exec touch -t 202601010000.00 {} +
( cd "$RELEASE_DIR" && find . -type f ! -name MANIFEST.sha256 \
    | sed 's|^\./||' | LC_ALL=C sort \
    | zip -q -X "$ZIP_PATH" -@ && zip -q -X "$ZIP_PATH" MANIFEST.sha256 )

# ── 4. SELF-CHECK: zip content list (checker m4) — every co-shipped piece
#       must be present, else exit non-zero. ──────────────────────────────
echo "==> self-check zip content list"
REQUIRED=(
  "$PKG_NAME/Manifest.json"
  "$PKG_NAME/Data/com.apple.CoreML/model.mlmodel"
  "$PKG_NAME/Data/com.apple.CoreML/weights/weight.bin"
  "LICENSE"
  "NOTICE"
  "MANIFEST.sha256"
)
LISTING=$(/usr/bin/zipinfo -1 "$ZIP_PATH")
for entry in $REQUIRED; do
  if ! grep -qx "$entry" <<<"$LISTING"; then
    echo "!! zip is missing required entry: $entry" >&2
    exit 1
  fi
done
# The NOTICE attribution lines (the in-AC assertion face).
for marker in "Depth Anything" "apple/coreml-depth-anything-v2-small"; do
  grep -q "$marker" "$RELEASE_DIR/NOTICE" \
    || { echo "!! NOTICE missing attribution: $marker" >&2; exit 1; }
done

# ── 5. Digest + sentinel rewrite (the build_default_bundle.sh pattern) ───
ZIP_SHA=$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)
ZIP_BYTES=$(stat -f%z "$ZIP_PATH")
echo "==> zip: $ZIP_BYTES bytes sha256=$ZIP_SHA"

uv run python - "$DIGESTS_SWIFT" "$SENTINEL" "$ZIP_SHA" "$ZIP_BYTES" <<'PYEOF'
import re, sys
from datetime import datetime, timezone
from pathlib import Path

swift_path, sentinel, sha, count = Path(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4])
generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
literal = (
    "ModelAssetDigestEntry(sha256Hex: \"%s\", byteCount: %d, "
    "auxiliaryFiles: [], generatedAt: \"%s\")" % (sha, count, generated_at)
)
text = swift_path.read_text()
pattern = re.compile(
    r"private static let %s: ModelAssetDigestEntry\? = .*?(?=\n\n)" % sentinel,
    re.DOTALL,
)
text, n = pattern.subn(
    lambda m: "private static let %s: ModelAssetDigestEntry? = %s" % (sentinel, literal),
    text,
)
if n != 1:
    raise SystemExit(f"sentinel not found (or not unique) for {sentinel}")
swift_path.write_text(text)
print(f"== {sentinel}: {count} bytes sha256={sha[:16]}... digest published")
PYEOF

echo "==> done. Release-upload step (T8 ops):"
echo "    gh release upload ai-models-v1 $ZIP_PATH"
