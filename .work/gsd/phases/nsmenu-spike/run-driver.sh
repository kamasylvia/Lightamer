#!/bin/zsh
# run-driver.sh — three-arm interleaved driver (AR-01 + L082).
#   A = main-tip build (+ probe-stay measurement hunk only), no bridge code
#   B = spike build, flag ON  (defaults write la.menu.nsmenuBridge true)
#   C = spike build, flag OFF (defaults write la.menu.nsmenuBridge false;
#       identical binary to B — the flag is the only delta)
# NOTE (measured 2026-10-19): passing the flag as a launch argument
# (`-la.menu.nsmenuBridge 1`) breaks window creation in the mixed-argv
# launch line — the flag rides defaults instead, argv identical for B/C.
# Interleaved rounds decorrelate slow drift; 3 rounds x 3 arms.
set -u
BIN_A=/tmp/nsmenu-spike-bin/A/Lightamer.app/Contents/MacOS/Lightamer
BIN_BC=/tmp/nsmenu-spike-bin/B/Lightamer.app/Contents/MacOS/Lightamer
BASE=/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/nsmenu-spike
DOM=com.kamasylvia.lightamer

# ── defaults: suppress the AI labeling ask (AR-01 F-8 §4), save priors ──
prev=$(defaults read "$DOM" library.ai.labelingMode 2>/dev/null || echo UNSET)
print "prior labelingMode=$prev" > "$BASE/logs/defaults-state.txt"
defaults write "$DOM" library.ai.labelingMode never

cleanup() {
    if [[ "$prev" == "UNSET" ]]; then
        defaults delete "$DOM" library.ai.labelingMode 2>/dev/null
    else
        defaults write "$DOM" library.ai.labelingMode "$prev"
    fi
    defaults delete "$DOM" la.menu.nsmenuBridge 2>/dev/null
    print "restored labelingMode=$prev; spike flag deleted" >> "$BASE/logs/defaults-state.txt"
}
trap cleanup EXIT

for round in r1 r2 r3; do
    defaults write "$DOM" la.menu.nsmenuBridge -bool false
    "$BASE/run-one.sh" "A-$round" "$BIN_A" || print "A-$round FAILED" >> "$BASE/logs/driver.txt"
    defaults write "$DOM" la.menu.nsmenuBridge -bool true
    "$BASE/run-one.sh" "B-$round" "$BIN_BC" || print "B-$round FAILED" >> "$BASE/logs/driver.txt"
    defaults write "$DOM" la.menu.nsmenuBridge -bool false
    "$BASE/run-one.sh" "C-$round" "$BIN_BC" || print "C-$round FAILED" >> "$BASE/logs/driver.txt"
done
print "driver complete $(date)" >> "$BASE/logs/driver.txt"
