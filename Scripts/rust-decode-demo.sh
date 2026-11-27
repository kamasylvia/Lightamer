#!/bin/bash
# rust-decode-demo.sh — B2 wave demo: RAW decode, raster decode, EXIF optics,
# embedded thumbnails, corrupt inputs, and the CR3 gap, on CC0 samples.
#
# Runs the release-built `decode --dump`: six printed steps (quadWord table,
# nine-sample timings, five corrupt inputs, thumbnails, CR3, cleanup).
# Everything runs in the demo's own temp dir with CC0 samples plus small
# self-made fixtures: no user photo library reads. Exits 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lightamer-decode-demo-XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

say() { printf '\n==> %s\n' "$1"; }
fail() { echo "demo: FAIL: $1" >&2; exit 1; }

SAMPLES="$HOME/Library/Application Support/Lightamer/TestRAW"
ARW="$SAMPLES/7RM5-LosslessCompressedLarge.ARW"
RAF="$SAMPLES/DSCF0021.RAF"
NEF="$SAMPLES/Nikon_Z8_raw_14_bit_lossless_compression.NEF"
DNG="$SAMPLES/5G4A9394-compressed-lossless.DNG"
CR3="$SAMPLES/IMG_4276.CR3"

"$ROOT/Scripts/machine-guard.sh"
(cd "$ROOT" && cargo build --release -p lightamer-cli --locked -j6)
CLI="$ROOT/target/release/lightamer-cli"

grab() { grep -m1 "^$2: " "$1" | sed "s/^$2: //"; }

say "step 1: quad (WxH, black, white, WB) + cold ms for ARW/RAF/NEF"
printf '%-12s %-11s %-7s %-7s %-24s %s\n' "sample" "WxH" "black" "white" "wb" "cold_ms"
for sample in "$ARW" "$RAF" "$NEF"; do
    name="$(basename "$sample")"
    "$CLI" decode --dump "$sample" > "$TMP/step1.log" || fail "dump $name"
    w="$(grab "$TMP/step1.log" width)"; h="$(grab "$TMP/step1.log" height)"
    black="$(grab "$TMP/step1.log" black)"; white="$(grab "$TMP/step1.log" white)"
    wb="$(grab "$TMP/step1.log" wb)"; ms="$(grab "$TMP/step1.log" decode_ms_cold)"
    printf '%-12s %-11s %-7s %-7s %-24s %s\n' "${name:0:12}" "${w}x${h}" "$black" "$white" "$wb" "$ms"
done
# (Never pipe the CLI into `grep -q`: the early pipe close panics Rust's
# stdout. Always dump to a file, then grep the file.)
"$CLI" decode --dump "$ARW" > "$TMP/arw.log" || fail "ARW dump"
grep -q "wb: 2536,1024,1778,0" "$TMP/arw.log" || fail "ARW WB drifted"
grep -q "exposure_time: 0.0005" "$TMP/arw.log" || fail "ARW shutter missing"
grep -q "lens_model: FE 50mm F1.2 GM" "$TMP/arw.log" || fail "ARW lens missing"

say "step 2: per-sample cold decode ms for all nine samples"
printf '%-46s %-8s %s\n' "sample" "kind" "cold_ms_or_error"
for sample in "$SAMPLES"/*; do
    name="$(basename "$sample")"
    if "$CLI" decode --dump "$sample" > "$TMP/step2.log" 2> "$TMP/step2.err"; then
        kind="raw"; grep -q "^kind: raster" "$TMP/step2.log" && kind="raster";
        ms="$(grab "$TMP/step2.log" decode_ms_cold)"
        printf '%-46s %-8s %s\n' "$name" "$kind" "$ms"
    else
        printf '%-46s %-8s %s\n' "$name" "ERROR" "$(head -n1 "$TMP/step2.err")"
    fi
done

say "step 3: five corrupt inputs report typed errors; the process survives"
: > "$TMP/empty.ARW"
python3 -c "import sys; state=0x243F6A8885A30B8D; out=bytearray();
for _ in range(1<<20):
    state ^= state >> 12; state ^= (state << 25) & 0xFFFFFFFFFFFFFFFF; state ^= state >> 27
    out.append((state * 0x2545F4914F6CDD1D >> 56) & 0xFF)
sys.stdout.buffer.write(bytes(out))" > "$TMP/random.ARW"
python3 -c "import sys; data=open('$ARW','rb').read(); sys.stdout.buffer.write(data[:len(data)//2])" > "$TMP/truncated.ARW"
python3 -c "import sys; sys.stdout.buffer.write(open('$ARW','rb').read(65536))" > "$TMP/headeronly.ARW"
cp "$SAMPLES/Nikon_Z8_raw_14_bit_lossless_compression-preview4.jpg" "$TMP/renamed.ARW"
for bad in empty random truncated headeronly renamed; do
    if "$CLI" decode --dump "$TMP/$bad.ARW" > "$TMP/bad.log" 2> "$TMP/bad.err"; then
        echo "$bad: exit=0 ($(grab "$TMP/bad.log" kind 2>/dev/null || echo raw) routed by content)"
    else
        echo "$bad: exit=$? $(head -n1 "$TMP/bad.err")"
    fi
done
"$CLI" decode --dump "$RAF" > /dev/null || fail "valid decode after corrupt run"
echo "survival: a valid RAF still decodes after all five"

say "step 4: embedded thumbnails (bytes, format, decoded size)"
printf '%-12s %-8s %-8s %s\n' "sample" "format" "bytes" "dims"
for sample in "$ARW" "$RAF" "$NEF" "$DNG"; do
    name="$(basename "$sample")"
    "$CLI" decode --dump "$sample" --thumb "$TMP/thumb.bin" > "$TMP/step4.log" \
        || fail "thumb $name"
    fmt="$(grab "$TMP/step4.log" thumbnail_format)"
    bytes="$(grab "$TMP/step4.log" thumbnail_bytes)"
    dims="$(grab "$TMP/step4.log" thumbnail_dims)"
    printf '%-12s %-8s %-8s %s\n' "${name:0:12}" "$fmt" "$bytes" "$dims"
    [ "$(wc -c < "$TMP/thumb.bin" | tr -d ' ')" = "$bytes" ] || fail "thumb size mismatch $name"
done
"$CLI" decode --dump "$ARW" --thumb "$TMP/t.bin" > "$TMP/t.log" || fail "ARW thumb dump"
grep -q "thumbnail_bytes: 9405" "$TMP/t.log" || fail "ARW thumb drifted"
"$CLI" decode --dump "$DNG" --thumb "$TMP/t.bin" > "$TMP/t.log" || fail "DNG thumb dump"
grep -q "thumbnail_format: raw" "$TMP/t.log" || fail "DNG raw thumb missing"

say "step 5: CR3 reports unsupported (this rawspeed pin has no CR3 decoder)"
if "$CLI" decode --dump "$CR3" > "$TMP/cr3.log" 2> "$TMP/cr3.err"; then
    fail "CR3 unexpectedly decoded"
else
    echo "CR3: exit=$? $(head -n1 "$TMP/cr3.err")"
fi
grep -q "not a supported RAW file" "$TMP/cr3.err" || fail "CR3 message drifted"

say "step 6: hygiene (temp dir removed, nothing left behind)"
rm -rf "$TMP"
trap - EXIT
leftovers="$(ls "${TMPDIR:-/tmp}" 2>/dev/null | grep -E "lightamer-decode-demo-" || true)"
[ -z "$leftovers" ] || fail "leftover temp dirs: $leftovers"
echo "demo: ALL GREEN"
