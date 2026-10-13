#!/bin/zsh
set -u
WS="/Volumes/UNITEK/Documents/Development/Lightamer"
slugs="m2-0 m2-1 m2-2 m2-3 m2-4 m2-5 m2-6 m2-7 m2-8 m2-9 m2-10 m2-11 m3-0 m3-1 m3-2 m3-3"
declare -A dir=(
  [m2-0]="m3-4-latitude" [m3-0]="m3-4-latitude"
  [m2-1]="m2-1-dt-disable" [m2-2]="m2-2-library-project" [m2-3]="m2-3-ui-shell"
  [m2-4]="m2-4-node-model" [m2-5]="m2-5-color-grade" [m2-6]="m2-6-drt"
  [m2-7]="m2-7-masks" [m2-8]="m2-8-versions" [m2-9]="m2-9-export"
  [m2-10]="m2-10-ai-library" [m2-11]="m2-11-performance"
  [m3-1]="m3-1-w1" [m3-2]="m3-2-fsim-research" [m3-3]="m3-3-fsim"
)
declare -A rep=(
  [m2-0]="M2-0" [m2-1]="M2-1" [m2-2]="M2-2" [m2-3]="M2-3" [m2-4]="M2-4"
  [m2-5]="M2-5" [m2-6]="M2-6" [m2-7]="M2-7" [m2-8]="M2-8" [m2-9]="M2-9"
  [m2-10]="M2-10" [m2-11]="M2-11" [m3-0]="M3-0" [m3-1]="M3-1" [m3-2]="M3-2" [m3-3]="M3-3"
)
printf "| %-7s | %-14s | %-14s | 判定 |\n" phase omp pi
printf "|---------|----------------|----------------|------|\n"
for s in ${=slugs}; do
  d="$WS/.work/gsd/phases/${dir[$s]}"
  r="${rep[$s]}"
  ov=$(tail -1 "$d/$r-ACCEPTANCE-OMP-R2.md" 2>/dev/null | sed 's/.*: *//' )
  [[ -z "$ov" ]] && ov="MISSING"
  pv=$(tail -1 "$d/$r-ACCEPTANCE-PI.md" 2>/dev/null | sed 's/.*: *//')
  [[ -z "$pv" ]] && pv="MISSING"
  judge="一致"; [[ "$ov" != "$pv" ]] && judge="分歧"
  printf "| %-7s | %-14s | %-14s | %s |\n" "$s" "$ov" "$pv" "$judge"
done
