#!/bin/bash
# Plan 01-05 spike samples — CC0 from raw.pixls.us (per-file provenance in samples/README.md)
source "$HOME/.config/xray/proxy.bash"
BASE="https://raw.pixls.us/data"
DEST="/Volumes/UNITEK/Documents/Development/Lightamer/.work/01-05/samples"
declare -a URLS=(
  "Fujifilm/GFX100S/Fujifilm-GFX100S-14bits-losslescompressed-4_3.RAF"
  "Sony/ILCE-7RM5/7RM5-LosslessCompressedLarge.ARW"
  "Nikon/Z%208/Nikon_Z8_raw_14_bit_lossless_compression.NEF"
  "Sony/ILCE-6700/DSC00001.ARW"
  "Canon/EOS%20R10/IMG_4276.CR3"
  "Fujifilm/X-T5/DSCF0021.RAF"
  "Fujifilm/X100VI/DSCF0074.RAF"
  "Fujifilm/X-H2S/IMG-20221005-0665.raf"
  "OM%20System/OM-1%20Mark%20II/80mp-12bit-tripod.orf"
  "Apple/iPhone%2012%20Pro/IMG_1361.DNG"
  "Adobe%20DNG%20Converter/Canon%20EOS%205D%20Mark%20III/5G4A9394-compressed-lossless.DNG"
  "Hasselblad/X2D%20100C/B0000079.3FR"
  "Phase%20One/IQ4%20150MP/IQ4_150MP_L_14.iiq"
)
for u in "${URLS[@]}"; do
  f="$DEST/$(basename "$u" | sed 's/%20/-/g;s/?//g')"
  echo ">>> $u"
  curl -sSL --retry 2 -C - --max-time 1800 -o "$f" "$BASE/$u" || echo "FAILED: $u"
done
echo "ALL DONE"
ls -la "$DEST"
