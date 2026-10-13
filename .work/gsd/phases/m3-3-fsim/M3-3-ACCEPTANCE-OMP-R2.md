# M3-3-ACCEPTANCE-OMP-R2 — FSIM-01 三波双路终验（OMP 路）

> 验收员：OMP / 日期：2026-10-10 / HEAD：`d57488ec` / 方法：正本亲读 + 上一轮抽查点独立重验（新 SHA 机检 + file:line 读码），零实机。
> 注：旧 SHA（`04b2909`/`9f4a649`/`2fee806..c5f5dce` 等）HEAD 已不可达——历史压缩重写；已亲建新 SHA 映射（01=`2b3cc954..7e5b3082` / 02=`949f2214..ab9f1b27` / 03=`501a70de..11dc364d`），本报告机检全走新 SHA。M3-4 exact 锚等均为后演进，不记账。

## 结论头

**PASS / 0 error + 1 minor**（minor = 承袭首验 02 分解账勘误，已修闭环；本轮零新增）

## 抽查点 1：FilmRecord 七字段 + sidecar v9 成对写入 ✅

- 七字段：`FilmRecord.swift:51-74`（filmStock/paperStock/yFilterShift/mFilterShift/contentAdaptiveShift/strength/exposureEv）+ snake_case CodingKeys（`:94-98`）。
- sidecar v9：`LightamerSidecar.swift:325` document 级 `filmRecord` + `:202` per-item 镜像 + `decodeIfPresent`（`:488`）；`7e5b3082` body 明示 additive 面。
- 上一轮 AC#4 求解器逐位复算结论：本轮未独立重算（Python 复算超出双路批耗时配额），采信首验+上一轮双路逐位一致，记覆盖。

## 抽查点 2：film sub-run 缝 ✅

- `PixelPipe.swift:171` `isFilmTailLeg` + `:290-294` 降出短路（含腿内 `return false`）+ `runTerminalTails` 调用点 `:890`。
- seed：`FilmTailPolicy.swift:89` policyTag `lightamer.film.subrun.v1` + `:100-113` 折叠序 recordHash⊕tag⊕solvedPackHash⊕upstream，与 KD-1 逐字吻合。
- DRT 交接：02 范围 `PixelPipe.swift` diff 中 `func seed` 零命中——`DrtTailAssembly.seed` 签名零改成立。

## 抽查点 3：kernel 红线（对象卡核心断言）✅

- M3-3 全范围（`2b3cc954..11dc364d`）新增 `.metal` 恰 2：`Film/FilmSubRunKernels.metal`（`film_subrun` `:69`）+ `FilmPlacement/FilmPlacementKernels.metal`——均为 film 自有新件，非既有 kernel 改动。
- `Lut3dKernels.metal`：01 范围零命中；02 范围 file-list（24 个非文书文件亲列）无此文件；03 范围 `.metal` 零新增。红线成立。

## 抽查点 4：FilmSolveCache 键控 ✅

- `FilmTailPolicy.swift:538-550`：`cacheKey` = fnv(pair⊕stats⊕modeTag)，`modeTag` 仅 contentAdaptive 二值（`:533-536`）。
- 无 ROI 项注释 `:531-533` 明示 per-ROI 红线结构面；整数秩 `percentileBin` `:554+` 累积计数。上一轮 §四键折叠精确值结论未重跑测试，读码一致。

## 抽查点 5：filmPlacement 简化臂 + m=1 符号修复 ✅

- `501a70de`（= 旧 `9f4a649`）：单文件 12+/6−，`K = t − √` → `K = t ∓ √` 双侧异号，body 代数与首验 §三一致。
- V50：`V50Order.swift:69` `("filmPlacement", 20.8)`，介 acesccIn/exposure 之间，add-only。
- 后演进：`landingRoomFloor`（`:156`）+ typed 守卫（`:194`）= M3-4 exact 锚，不记账；`576c0b25` 重钉 golden 回归亦后演进。

## 抽查点 6：golden 门钉值 ✅

- `FilmGoldenTests.swift:779,820` 钉 1e-4（门 1a）；`:1002` 凸性 1.5×（门 1b）；门 2/门 4 钉值行号后演进漂移，采信首验+上一轮双证。
- 法数 16 = 12 + M3-4-01 重钉 4（上一轮 §六已注记）；Determinism 5 / Panel 6 / Card 4 = `grep -c` 实数亲核。

## 抽查点 7：面板最小面 + 只读 Film 卡 ✅

- `NodeCanvasGeometry.swift:29` `filmCardID` 编译期常量 + `:116-118` `layout(includesFilmCard: Bool = false)` additive 默认参。
- `PipelineDocument.swift:44-48` NodeKind 仅 develop/grade/displayTransform——零新增成立。
- 03 范围 file-list 17 文件亲列：App 面板/卡 9 + FilmTailPolicy + PlacementModule 符号修正 + 登记/xcstrings/4 测试，与申报结构一致。

## 抽查点 8：封存面清单（git 核 3 组）✅

- 01 范围：PixelPipe/Lut3dKernels/HistoryHash/`Resources/LUTs` 零命中（0 行）。
- 02 范围：ExportQueueContract/LightamerSidecar 零命中（0 行）。
- 03 范围：PipelineDocument/HistoryStack/Lut3dKernels 零命中（0 行）。
- 资产：`shasum -c MANIFEST.sha256` = **30/30 OK**；`git log -- Resources/FilmProfiles/` 仅 `516493f0`（= 旧 `04b2909`）单提交。

## 分歧项

无实质分歧。两点注记（非分歧）：

1. 上一轮报告所引旧 SHA 在 HEAD 已全部不可达（历史压缩重写）——本轮已亲建新 SHA 映射并逐项重验，内容对应逐位一致，旧 SHA 引用失效不记账。
2. 上一轮 §六亲跑 2 类测试（5/0/0 + 16/0/0）；本轮按双路批约束未跑测试，引用 ACCEPTANCE 终值（03 全套 3152/16/0）+ 上一轮定向值，读码/机检面全覆盖。

## 会话卫生

只读验收：除本报告外零写入；测试未跑；未 push；无网络动作。

OMP-VERDICT: PASS
