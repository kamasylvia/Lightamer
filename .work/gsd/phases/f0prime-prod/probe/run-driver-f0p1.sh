#!/bin/zsh
# run-driver-f0p1.sh — the D-6 gate driver (F0P-01 T7): THREE rounds of the
# flipped production binary (B arm), interleaved spacing, spike protocol.
set -u
BASE=/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/f0prime-prod/probe
DOM=com.kamasylvia.lightamer
BIN_B=/tmp/f0p1-dd-B/Build/Products/Debug/Lightamer.app/Contents/MacOS/Lightamer

prev=$(defaults read "$DOM" library.ai.labelingMode 2>/dev/null || echo UNSET)
print "prior labelingMode=$prev" > "$BASE/logs/defaults-state.txt"
defaults write "$DOM" library.ai.labelingMode never

cleanup() {
    if [[ "$prev" == "UNSET" ]]; then
        defaults delete "$DOM" library.ai.labelingMode 2>/dev/null
    else
        defaults write "$DOM" library.ai.labelingMode "$prev"
    fi
    print "restored labelingMode=$prev" >> "$BASE/logs/defaults-state.txt"
}
trap cleanup EXIT

for round in B-r1 B-r2 B-r3; do
    "$BASE/run-one-f0p1.sh" "$round" "$BIN_B" \
        || print "$round FAILED" >> "$BASE/logs/driver.txt"
done
print "driver complete $(date)" >> "$BASE/logs/driver.txt"
