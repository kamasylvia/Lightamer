# M9-2 改签批 review 修复 lane（omp）

你是 M9-2 改签批的修复执行者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文，commit 英文。当前 HEAD = `e63ebb3f`（先亲核）。

## 输入（唯一对照源）

`.work/gsd/phases/m9-2-bwspectral/M9-2BW-REVIEW.md`（zcode 独立审核报告，PASS / 0 error + 3 minor）——**只修三个 minor**，obs 不动产品（obs-b 账本措辞可顺手，见下）。

## 修复清单

1. **minor-1**（SpectralProfileDecodeTests.swift:261）：`XCTAssertGreaterThanOrEqual(nulls, 0)` 恒真空断言 + 原紧致门 de-pin 未披露。修法按报告建议：把 `:300` 的 `isBWPack` 判定提升到该断言之前，改为 `XCTAssertGreaterThanOrEqual(nulls, isBWPack ? 0 : 15)`（或 BW 分支显式 `== 0`）——恢复存量卷 ≥15 紧致语义。
2. **minor-2**（FilmProfile.swift:225/:640）：删除死公开 API `logSensitivityProjected()`（全仓零调用）；字段注释改为「null 读作零灵敏度，禁插值」（对齐上游 nan_to_num→0 物理）。删除前 `grep -rn "logSensitivityProjected" --include="*.swift"` 确认零调用，删除后同样确认零残留。
3. **minor-3**（SpectralDualArmGoldenTests.swift:618）：`differingPairs > 25` 随 28→31 上调为 `> 28`（93%→84% 分叉率下限，31/31 实测有余量）。
4. **obs-b（docs 顺手）**：`M9-2-SUMMARY.md` 账本段把「4529−4443=+86」同义反复改为分段链式列表（4443(r9)→4462→4514→4516→4520→+0→+9→4529→4533），不改数值。

## 纪律

- 单 commit 收口：`fix(m92): review round — restore nulls pin, drop dead API, raise dual-arm threshold`（body 逐条 finding→fix 映射 + 验证方法）；docs 账本改动并入同 commit 或紧随 docs commit 二选一。
- 封存面 17 件零 diff；RenderProcess 恒 3；`Resources/FilmProfiles/` 零 diff。
- 定向复跑（机器 guard 先行，禁 --all）：`SpectralProfileDecodeTests` + `SpectralDualArmGoldenTests` + `FilmProfileTests` 三类（test-direct 定向，跑完清场）。
- zh-audit `--check` 复跑。
- 零 push、零新文件（除报告）、stdout 最后一条一次性完整输出（逐 finding 修法/定向终值/commit SHA/封存面声明）。
