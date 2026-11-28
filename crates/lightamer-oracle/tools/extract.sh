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
    hotpixels)
      cat <<'EOF'
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|35-41,43-50,52-61|hotpixels_types.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|105-158|hotpixels_bayer.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|161-216|hotpixels_mono.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|219-325|hotpixels_xtrans.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|327-356|hotpixels_process.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|358-366|hotpixels_defaults.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|368-385|hotpixels_commit.inc
dt|release-5.7.0|src/iop/hotpixels.c|ca687dd10b2b325e075cff90cfbf8106f8f94ebe|387-398|hotpixels_pipe.inc
dt|release-5.7.0|src/develop/imageop_math.h|8bc306cc396ee25ae5b9eb5c38fb6ddafadba96f|195-207|hotpixels_fcn.inc
dt|release-5.7.0|src/develop/pixelpipe_hb.c|d6f1d1bb33489b70959b5b7ae76028ade2e05a28|1289-1304|piece_cfa.inc
dt|release-5.7.0|src/develop/pixelpipe_hb.h|0c0acea088195aa313d410cc76b2ce88157ec044|272-283|pipe_predicates.inc
dt|release-5.7.0|src/develop/pixelpipe.h|e0dce53737eeba5bf6ee8d61bb3ce111cdccde6b|41-57|pipe_type_enum.inc
EOF
      ;;
    temperature)
      cat <<'EOF'
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|48-64|temperature_defs.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|68-75,77-99,101-105|temperature_types.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|185-199|temperature_array.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|201-236|temperature_ignore.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|281-403|temperature_spectrum.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|406-502|temperature_convert.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|504-639|temperature_process.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|687-728|temperature_commit.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|730-743|temperature_pipe.inc
dt|release-5.7.0|src/iop/temperature.c|eee5d23ab7d86cbd2999bf6c469cd388d99464b7|1382-1511|temperature_coeffs.inc
dt|release-5.7.0|src/develop/imageop_math.h|8bc306cc396ee25ae5b9eb5c38fb6ddafadba96f|154-157,195-207|temperature_fcn.inc
dt|release-5.7.0|src/common/dttypes.h|f875f6a6f1ee1f07c30dc8d970b0d7ede5af0ab1|57-57,68-72,94-114|temperature_simd.inc
dt|release-5.7.0|src/common/dttypes.h|f875f6a6f1ee1f07c30dc8d970b0d7ede5af0ab1|231-259|temperature_colormatrix.inc
dt|release-5.7.0|src/common/math.h|689dc1061abd42553ac066fffc3dd6645011ae7c|114-117|temperature_isnormal.inc
dt|release-5.7.0|src/common/colorspaces.h|9b01c35057afed8a3708198c1018b727ba0d82ac|37-38|temperature_d65.inc
dt|release-5.7.0|src/common/colorspaces.c|c3fc7d6d8bd39a30b5b3b879a0848009f96289d3|2311-2456|temperature_matrices.inc
dt|release-5.7.0|src/common/image.c|05605921dc2f684cf3419820f7e09d850e157489|253-257|temperature_matrix_pred.inc
dt|release-5.7.0|src/develop/pixelpipe_hb.h|0c0acea088195aa313d410cc76b2ce88157ec044|292-295|temperature_preview_pred.inc
dt|release-5.7.0|src/external/cie_colorimetric_tables.c|051340d06de32e69f2609496dc42cef33f51675d|1-230|temperature_cie_tables.inc
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
