#!/usr/bin/env bash
# bench.sh — one command to reproduce the issue #24 experience-speed matrix.
#
#   ./bench.sh                 # full run (10 timed reps/cold row)
#   ./bench.sh --quick         # 5 reps (smoke)
#   SPIKE_ROOT=... ./bench.sh  # non-default spike workspace
#
# Heavy work (third-party sources, builds, 122 MB DNGs) lives OUTSIDE the repo at
# $SPIKE_ROOT (default: /Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike).
# Only the CSV lands in this evidence directory.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../../.." && pwd)"
SPIKE_ROOT="${SPIKE_ROOT:-/Volumes/UNITEK/Documents/Development/Lightamer-rawspeed-spike}"
QUICK="${1:-}"
cd "$SPIKE_ROOT"

exec > >(tee "$HERE/bench-run.log") 2>&1
echo "== environment =="
sw_vers | head -3
swift --version 2>&1 | head -2
sysctl -n machdep.cpu.brand_string
echo "spike root: $SPIKE_ROOT"

echo "== machine guard =="
if [ -x "$REPO/Scripts/machine-guard.sh" ]; then
  "$REPO/Scripts/machine-guard.sh" --wait || { echo "machine busy, aborting"; exit 1; }
fi
memory_pressure | tail -2 || true

RS="$SPIKE_ROOT/rawspeed"
BUILD="$SPIKE_ROOT/build/rawspeed"
if [ ! -f "$RS/data/cameras.xml" ]; then
  echo "rawspeed sources missing under $RS — clone darktable-org/rawspeed (pin 718eae230df9ebb1750755b775e52185f2342a46) first" >&2
  exit 1
fi

echo "== rawspeed static library =="
if [ ! -f "$BUILD/librawspeed.a" ]; then
  cmake -S "$RS" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 \
    -DBUILD_TESTING=OFF -DBUILD_TOOLS=ON -DBUILD_BENCHMARKING=OFF -DBUILD_FUZZERS=OFF -DBUILD_DOCS=OFF \
    -DWITH_OPENMP=ON -DCMAKE_CXX_FLAGS="-I/opt/homebrew/opt/libomp/include" >/dev/null
  cmake --build "$BUILD" -j 4
fi

echo "== helpers =="
CFLAGS=(-std=c++20 -O2 -arch arm64 "-I$RS/src/librawspeed" "-I$BUILD/src"
        -isystem "$RS/src/external" -I/opt/homebrew/opt/libomp/include)
LIBS=("-L$BUILD" -lrawspeed -L/opt/homebrew/opt/libomp/lib -lomp
      -L/opt/homebrew/opt/pugixml/lib -lpugixml -L/opt/homebrew/opt/libjpeg-turbo/lib -ljpeg -lz)
[ -x bin/rsprobe ] || c++ "${CFLAGS[@]}" bin/rsprobe.cpp -o bin/rsprobe "${LIBS[@]}"
[ -x bin/rs2dng ] || c++ "${CFLAGS[@]}" bin/rs2dng.cpp -o bin/rs2dng "${LIBS[@]}"
[ -x bin/lrbench ] || c++ -std=c++20 -O2 -arch arm64 -I/opt/homebrew/include bin/lrbench.cpp -o bin/lrbench -L/opt/homebrew/lib -lraw
[ -x bin/xcheck ] || c++ "${CFLAGS[@]}" -I/opt/homebrew/include bin/xcheck.cpp -o bin/xcheck "${LIBS[@]}" -L/opt/homebrew/lib -lraw
[ -x bin/bench ] || swiftc -O -swift-version 6 -parse-as-library -o bin/bench bin/bench.swift

# benchlive = the honest P1 first-open path: shim decode -> in-memory DNG -> CIRAW.
if [ ! -x bin/benchlive ] || [ bin/benchlive -ot bin/benchlive.swift ] || [ bin/benchlive -ot shim/.build/out/Products/Release/CRawSpeedShim.o ]; then
  ( cd shim && swift build -c release -j 4 >/dev/null )
  SRC=shim
  MOD=$PWD/$SRC/.build/out/Intermediates.noindex/GeneratedModuleMaps
  CACHE=$(ls -d "$PWD/$SRC"/.build/out/ModuleCache.noindex/* | head -1)
  swiftc -O -swift-version 6 -parse-as-library -cxx-interoperability-mode=default \
    -o bin/benchlive bin/benchlive.swift \
    -I "$MOD" -Xcc -fmodule-map-file="$MOD/CRawSpeedShim.modulemap" \
    -Xcc -fmodules -Xcc -fmodules-cache-path="$CACHE" \
    -Xcc -I"$PWD/$SRC/Sources/CRawSpeedShim/include" -Xcc -I"$PWD/bin" \
    -Xcc -I"$RS/src/librawspeed" -Xcc -I"$BUILD/src" -Xcc -isystem -Xcc "$RS/src/external" \
    -Xcc -I/opt/homebrew/opt/libomp/include -Xcc -std=c++20 \
    "$PWD/$SRC/.build/out/Products/Release/CRawSpeedShim.o" \
    -L"$BUILD" -lrawspeed -L/opt/homebrew/opt/libomp/lib -lomp \
    -L/opt/homebrew/opt/pugixml/lib -lpugixml -L/opt/homebrew/opt/libjpeg-turbo/lib -ljpeg -lz
fi

echo "== T1 probe =="
./bin/rsprobe "$RS/data/cameras.xml" samples/7RM5-LosslessCompressedLarge.ARW | tee "$HERE/t1-a7r5-meta.txt"

echo "== cross-check: rawspeed vs LibRaw mosaic =="
./bin/xcheck "$RS/data/cameras.xml" samples/7RM5-LosslessCompressedLarge.ARW | tee "$HERE/xcheck.txt"

echo "== form B (C ABI shim) =="
SHIMBIN=""
for c in shim/.build/out/Products/Release/RSShimProbe shim/.build/out/Products/Debug/RSShimProbe; do
  if [ -x "$c" ]; then SHIMBIN="$c"; break; fi
done
if [ -n "$SHIMBIN" ]; then
  { "$SHIMBIN" "$RS/data/cameras.xml" "$SPIKE_ROOT/samples/7RM5-LosslessCompressedLarge.ARW"; echo "EXIT=$?"; } > "$HERE/t3-shim.log" 2>&1
  echo "=== corrupt input (error path) ===" >> "$HERE/t3-shim.log"
  { echo "not a raw file" > /tmp/bogus.raw; "$SHIMBIN" "$RS/data/cameras.xml" /tmp/bogus.raw; echo "EXIT=$?"; } >> "$HERE/t3-shim.log" 2>&1
  cat "$HERE/t3-shim.log"
else
  echo "shim probe not built (cd shim && swift build -c release -j 4) — skipping T3 rerun" | tee "$HERE/t3-shim.log"
fi

echo "== P1 DNG ladder (rawspeed mosaic -> uncompressed CFA DNG) =="
mkdir -p work
for ds in 0 1 2; do
  ./bin/rs2dng "$RS/data/cameras.xml" samples/7RM5-LosslessCompressedLarge.ARW "work/a7r5-ds$ds.dng" --downsample "$ds"
done

echo "== P1 vs P0 coarse diff (2560 render) =="
./bin/bench cmp samples/7RM5-LosslessCompressedLarge.ARW work/a7r5-ds0.dng | tee "$HERE/p0-vs-p1-cmp.txt"

echo "== experience-speed matrix =="
python3 "$HERE/benchrun.py" --root "$SPIKE_ROOT" --out "$HERE/bench.csv" $QUICK

echo
echo "== results =="
column -s, -t < "$HERE/bench.csv" 2>/dev/null || cat "$HERE/bench.csv"
