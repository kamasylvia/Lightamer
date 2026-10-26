#!/bin/zsh
# run-driver-f0p2-l2.sh — lane-2 acceptance D-6 retest driver (single B round).
# Consumes the lane-1 BUILD-HANDOFF container binary (no rebuild).
# labelingMode protection = driver convention; restoration target = ABSENT
# (pre-batch ground truth — acc1-defaults-state.txt prior=UNSET; the current
# "never" is the lane-1 aborted-chain residue, see acc2 acceptance report).
set -u
BASE=/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/f0prime-prod/probe
DOM=com.kamasylvia.lightamer
BIN_B=/Users/kamasylvia/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app/Contents/MacOS/Lightamer

prev=$(defaults read "$DOM" library.ai.labelingMode 2>/dev/null || echo ABSENT)
print "prior labelingMode=$prev (lane2; restore target = absent)" > "$BASE/logs/defaults-state-l2.txt"

cleanup() {
    if [[ "$prev" == "ABSENT" ]]; then
        defaults delete "$DOM" library.ai.labelingMode 2>/dev/null
    else
        defaults write "$DOM" library.ai.labelingMode "$prev"
    fi
    print "restored labelingMode=absent (pre-batch truth; prior residue was $prev)" >> "$BASE/logs/defaults-state-l2.txt"
}
trap cleanup EXIT

"$BASE/run-one-f0p1.sh" "d6-B-r4-l2" "$BIN_B" \
    || print "d6-B-r4-l2 FAILED" >> "$BASE/logs/driver-l2.txt"
print "lane2 driver complete $(date)" >> "$BASE/logs/driver-l2.txt"
