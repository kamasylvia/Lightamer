#!/bin/zsh
set -u
D="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/m3-4-latitude/retro-dual"
WS="/Volumes/UNITEK/Documents/Development/Lightamer"
cd "$WS" || exit 9
echo "[backfill] silent wait 7050s"
sleep 7050
for s in m2-3 m2-4 m2-10 m3-3; do
  echo "[backfill] $s start $(date +%H:%M)"
  perl -e 'alarm shift; exec @ARGV' 600 pi -p -a --model opencode-go/glm-5.3 --thinking high "$(cat "$D/prompts/$s-pi.txt")" > "$D/out/$s-pi-backfill.out" 2>&1
  echo "[backfill] $s EXIT=$? $(date +%H:%M)"
  sleep 120
done
echo "[backfill] ALL-DONE"
