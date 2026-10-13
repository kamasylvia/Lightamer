#!/bin/zsh
set -u
D="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/m3-4-latitude/retro-dual"
WS="/Volumes/UNITEK/Documents/Development/Lightamer"
cd "$WS" || exit 9
echo "[batch] sleeping 16700s for quota window..."
sleep 16700
echo "[batch] window reset, running m3-2 dual"
zsh "$D/run-phase.zsh" m3-2
echo "[batch] running m3-3 dual"
zsh "$D/run-phase.zsh" m3-3
for s in m2-3 m2-4 m2-10 m3-1; do
  echo "[batch] backfill PI $s"
  sleep 90
  perl -e 'alarm shift; exec @ARGV' 600 pi -p -a --model opencode-go/glm-5.3 --thinking high "$(cat "$D/prompts/$s-pi.txt")" > "$D/out/$s-pi-backfill.out" 2>&1
  echo "[batch] backfill $s EXIT=$?"
done
echo "[batch] ALL-DONE"
