#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Re-extracts verbatim upstream fragments into ../upstream/ (default), or
# verifies the committed copies byte-for-byte (--check).
#
# Usage: tools/extract.sh <module> [--check]
#
# The darktable reference clone arrives via LIGHTAMER_DT_REF (read-only; the
# script never writes there). rawspeed comes from the workspace submodule
# external/rawspeed. Either missing -> SKIP (exit 0), never a failure: the
# committed copies are the build input, extraction is only provenance.
set -eu

mod="${1:?usage: extract.sh <module> [--check]}"
mode="${2:-}"
here="$(cd "$(dirname "$0")" && pwd)"
crate_dir="$(cd "$here/.." && pwd)"
ws_root="$(cd "$crate_dir/../.." && pwd)"
tmp=
trap 'rm -rf "$tmp"' EXIT

# Manifest: repo|rev|path|blob|ranges|dest
# repo dt = $LIGHTAMER_DT_REF @ release-5.7.0, rs = workspace external/rawspeed.
manifest_for() {
  case "$1" in
    rawprepare)
      cat <<'EOF'
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|40-55,65-82|rawprepare_types.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|195-201|rawprepare_crop.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|253-286|rawprepare_roi.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|301-320|rawprepare_cfa.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|322-448|rawprepare_process.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|569-580|rawprepare_normalized.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|582-622|rawprepare_rawcrops.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|624-678|rawprepare_gainmaps.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|680-740|rawprepare_commit.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|742-751|rawprepare_pipe.inc
dt|release-5.7.0|src/iop/rawprepare.c|b344b0270ce19b761843440dd446800700efb6f1|753-777|rawprepare_defaults.inc
dt|release-5.7.0|src/common/image.c|05605921dc2f684cf3419820f7e09d850e157489|170-173,180-184,259-262|image_predicates.inc
dt|release-5.7.0|src/imageio/imageio_rawspeed.cc|7f7dabe7ff8ebbde2e09b822f192ade6e6112b19|119-127|rawspeed_crop.inc
dt|release-5.7.0|src/common/dng_opcode.h|a57d2c8533590f45be90f96161922e493f9af598|26-44|dng_gainmap_struct.inc
rs|0c16fee7772594e98897bded01fc31bc3409b4cb|src/librawspeed/metadata/ColorFilterArray.cpp|f349c81a96650bb187ecc4bdd2e0e30034fcff8d|143-170|shift_dcraw.inc
EOF
      ;;
    *) echo "extract.sh: unknown module '$1'" >&2; exit 2 ;;
  esac
}

# Prints one sed program for a comma-separated range list ("40-55,65-82").
sed_prog() {
  echo "$1" | tr ',' '\n' | sed 's/^\([0-9][0-9]*\)-\([0-9][0-9]*\)$/\1,\2p;/g' | tr -d '\n'
}

tmp="$(mktemp -d)"
manifest_for "$mod" >"$tmp/manifest.txt"
while IFS='|' read -r repo rev path blob ranges dest; do
  if [ "$repo" = "dt" ]; then
    if [ -z "${LIGHTAMER_DT_REF:-}" ] || [ ! -d "${LIGHTAMER_DT_REF:-}" ]; then
      echo "SKIP: LIGHTAMER_DT_REF unset or missing ($dest)"
      continue
    fi
    src="$LIGHTAMER_DT_REF"
  else
    src="$ws_root/external/rawspeed"
    if [ ! -d "$src/.git" ] && [ ! -f "$src/.git" ]; then
      echo "SKIP: $src not a checkout ($dest)"
      continue
    fi
  fi
  # Guard against tag/submodule drift before reading a single line.
  actual="$(git -C "$src" rev-parse "$rev:$path" 2>/dev/null || true)"
  if [ "$actual" != "$blob" ]; then
    echo "MISMATCH: $path @$rev blob is $actual, manifest wants $blob" >&2
    exit 1
  fi
  git -C "$src" show "$rev:$path" | sed -n "$(sed_prog "$ranges")" >"$tmp/$dest"
  want="$crate_dir/upstream/$dest"
  if [ "$mode" = "--check" ]; then
    if cmp -s "$tmp/$dest" "$want"; then
      echo "OK: $dest"
    else
      echo "DIFFERS: $dest" >&2
      exit 1
    fi
  else
    cp "$tmp/$dest" "$want"
    echo "wrote: $dest"
  fi
done <"$tmp/manifest.txt"
