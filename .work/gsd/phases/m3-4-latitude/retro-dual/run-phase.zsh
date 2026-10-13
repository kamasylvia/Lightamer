#!/bin/zsh
set -u
D="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/m3-4-latitude/retro-dual"
WS="/Volumes/UNITEK/Documents/Development/Lightamer"
slug="$1"
mkdir -p "$D/prompts" "$D/out"

{ print; cat "$D/COMMON.md" "$D/objects/$slug.md"; print '---'; print '【你的身份】OMP 路（验收员身份 = OMP）。只写 OMP 版报告（对象卡中 OMP 路径），报告末行 = OMP-VERDICT: PASS|FAIL|SKIPPED-PARTIAL。PI 版报告由并行另一路负责，禁止创建或改动。'; } > "$D/prompts/$slug-omp.txt"
{ print; cat "$D/COMMON.md" "$D/objects/$slug.md"; print '---'; print '【你的身份】PI 路（验收员身份 = PI）。只写 PI 版报告（对象卡中 PI 路径），报告末行 = PI-VERDICT: PASS|FAIL|SKIPPED-PARTIAL。OMP 版报告由并行另一路负责，禁止创建或改动。'; } > "$D/prompts/$slug-pi.txt"

cd "$WS" || exit 9
perl -e 'alarm shift; exec @ARGV' 600 omp -p --auto-approve --thinking max "$(cat "$D/prompts/$slug-omp.txt")" > "$D/out/$slug-omp.out" 2>&1 &
p1=$!
perl -e 'alarm shift; exec @ARGV' 600 pi -p -a --model opencode-go/glm-5.3 --thinking high "$(cat "$D/prompts/$slug-pi.txt")" > "$D/out/$slug-pi.out" 2>&1 &
p2=$!
wait $p1; e1=$?
wait $p2; e2=$?
echo "SLUG=$slug OMP_EXIT=$e1 PI_EXIT=$e2"
