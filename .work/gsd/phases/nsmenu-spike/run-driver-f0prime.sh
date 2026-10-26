#!/bin/zsh
# run-driver-f0prime.sh — two-arm interleaved driver (AR-01 + L082).
#   A = main tip + probe-stay hunk only (SwiftUI lifecycle; commit a35ad151)
#   B = F0' shell handover (manual NSApplication + NSHostingView + NSMenu;
#       commit c9a91562)
# No flags — the two arms are different binaries by construction.
# 3 interleaved rounds (A->B x3) decorrelate slow drift.
set -u
BIN_A=/tmp/f0prime-dd-A/Build/Products/Debug/Lightamer.app/Contents/MacOS/Lightamer
BIN_B=/tmp/f0prime-dd-B/Build/Products/Debug/Lightamer.app/Contents/MacOS/Lightamer
BASE=/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/nsmenu-spike
DOM=com.kamasylvia.lightamer

prev=$(defaults read "$DOM" library.ai.labelingMode 2>/dev/null || echo UNSET)
print "prior labelingMode=$prev" > "$BASE/f0prime-logs/defaults-state.txt"
defaults write "$DOM" library.ai.labelingMode never

cleanup() {
    if [[ "$prev" == "UNSET" ]]; then
        defaults delete "$DOM" library.ai.labelingMode 2>/dev/null
    else
        defaults write "$DOM" library.ai.labelingMode "$prev"
    fi
    print "restored labelingMode=$prev" >> "$BASE/f0prime-logs/defaults-state.txt"
}
trap cleanup EXIT

for round in r1 r2 r3; do
    "$BASE/run-one-f0prime.sh" "A-$round" "$BIN_A" \
        || print "A-$round FAILED" >> "$BASE/f0prime-logs/driver.txt"
    "$BASE/run-one-f0prime.sh" "B-$round" "$BIN_B" \
        || print "B-$round FAILED" >> "$BASE/f0prime-logs/driver.txt"
done
print "driver complete $(date)" >> "$BASE/f0prime-logs/driver.txt"
