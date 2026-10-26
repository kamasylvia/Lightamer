# M8-FIX 修正批 omp 复核（execute 道二次验收，computer-use 实机）

## 角色

omp 独立复核眼。你上一场终审报的 **M-1（probe 缝新档迁移行可见 / sidecar 缺 process 键）**已修复并过 zcode 验收——本场复核修复 + 对账验收报告。工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。全程中文。

## 必读

1. 你自己上场的报告 `.work/gsd/phases/m8-fsim-spectral/ACCEPTANCE-OMP.md` §M-1（你报的表型与根因候选）
2. `.work/gsd/phases/m8-fsim-spectral/M8-FIX-1-DECISIONS.md` + `M8-FIX-1-SUMMARY.md`（真根因与修复——注意 omp 两候选均被证伪，第三机制定罪 = closeEditor 丢弃 process 载体）
3. `.work/gsd/phases/m8-fsim-spectral/M8-FIX-ACCEPTANCE.md`（zcode 验收 PASS/0B+0M+0m+3obs——你对账对象）

## 机器与卫生

- 唯一 GUI 占用者；`Scripts/machine-guard.sh --wait`；同链 ps 清零；`--monitor 7200 &` 伴跑。
- 复用现成构建：`~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app`（含修复 `7422401a`）。
- 禁改源码；收工 tracked 零 diff；GUI quit；defaults 清。

## 复核职责（实机）

1. **M-1 原配方复走**：你上场的 probe 缝配方 + **正常用户路径腿**（⌘W/返回图库 → 图库态启用 Film）——核迁移行缺席 + readout 走 v2；quit 后重开核 sidecar 含 `process` 键（zcode 报 obs-2 称磁盘写腿被仪器面阻断、由测试 in-process 承载——你若能走通磁盘腿则实测之，走不通如实注记）。
2. **v1 老档对照**：真老档迁移行照常（判别力）。
3. **回归面**：迁移 UX 四面不回归（pristine/确认 sheet/渲染翻面/undo 边界抽查两面即可）。
4. **对账 zcode 报告**：其 obs-1（IOP skip −4 宿主态）/ obs-2 / obs-3 三条各评一句；R5 三件结论抽查（D-6 翻账依据 CPU 0.0% 是否可信——你可自测一次 40s 采样）。

## 产出契约

- 正本 `.work/gsd/phases/m8-fsim-spectral/M8-FIX-ACCEPTANCE-OMP.md`：结论头 `PASS / N B + N M + N m + N obs` + 逐面判定表 + 对账节。截图 `.work/gsd/phases/m8-fsim-spectral/fix-acceptance/omp/`。
- stdout 最终消息一次性完整输出（合并为一条）。
