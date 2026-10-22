# R12-REPAIRS SUMMARY — R1/R2 修复批接手收口（2026-10-22）

> 接手 = 上一任 executor token 耗尽死亡现场（30 tracked + 2 新文件未提交）。
> 本批完成：验证 + 补全 + 分组提交 + 测试 + 全套。HEAD 进入 = `652a496d`。

## 结论头

**PASS / 4 commits · 定向三 bundle 全绿 · 全套 `TOTAL|4106/40/0|`（= 4101 基线 + ΔN 5 精确对账）**

## 续接点

- 批次闭环：R1 首项（M-1）+ R2 卫生（35 处 + M-7）+ N-L 半截键闭合 + F2-4 +
  标记链断 write-face substrate 全部落账。
- **唯一大遗留 = 标记链断产线接线**（DECISIONS D5：shell apply\* → writer 的
  选择桥未开工，图库工作区标记命令仍 no-op）——下一修复批首项候选。
- R1 其余在账：M-2/M-3/M-4（E 族）、M-5/M-6、M-8/M-9、M-10..M-30（MANIFEST
  路由原样）。
- M-1 已知边界（pair 不变的 selection 变化重评）登记 DECISIONS D2，R3 顺路。

## 分组 commits（全英文 body 含根因）

| commit | 项 | 文件 |
|---|---|---|
| `f64593af` | M-1 CullingView pair 切换重载 | CullingView.swift（.task(id:) + decodeLeg 缝 + 显式 init）· CullingPipelineTests（新法 + tuple/NSLock/pump 三修）· BUNDLE-MAP（M-1 行） |
| `266647c1` | 标记链断 write-face substrate | LibraryMetadataWriter.swift（新）· LibraryStore.setMetadataMarks · LibraryGridModel.refreshRows(ids:) · LibraryMetadataWriterTests（新 4 法）· Project.swift · BUNDLE-MAP（LIB 行） |
| `926ba65d` | F2-4 SettingsLink repoint | ShellGraph.settingsRequested · LightamerShell face onChange · LibraryInspectorView（Button repoint + 注释清扫 + 该文件 3 处 R2 hunk 随批披露）· SettingsView stale 注释 |
| `41790826` | R2 卫生 + N-L 本地化 | 24 文件 overlay/background 尾闭包化 + verbatim/懒解析 + xcstrings 三键尾插一孤儿删 + RawDecode gamma 形修正 |

## 补全清单（存活 diff 审计 → 本批补完）

1. **M-1 产线修复未落** → `.task(id: [pair.0, pair.1])`（数组 id，tuple 不可
   Equatable）+ decodeLeg 显式 init 缝。
2. **CullingPipelineTests 三处编译残缺**（tuple 断言 / NSLock async / decodeLeg
   缺参）+ pump 阻塞饿死 MainActor（实测首 leg 记录后 B 永不启动）→ yield 式
   pump，6/0/0 绿。
3. **F2-4 未碰** → request-field + face 消费形落全，SettingsLink 代码面清零。
4. **标记链断 writer 半截** → OSLogMessage 拼接编译错修复合一插值；nil 分量
   语义反转校正（nil = 不动，测试正本）；投影 mark 改取合成后文档；
   @MainActor 类标注；refreshRows(ids:) 补齐。
5. **R2/N-L 半截键** → 三 catalog 条目补齐（manual）+ 孤儿 `rawdecode_raster_trc_gamma`
   删除 + gamma 读出 defaultValue:StaticString 编译错修为裸 LocalizationValue 形。
6. **R2 35 处全清**（机检零残留；余 3 命中 = 合法 `in:` 形/域函数）。

## 让渡登记

- **标记链断接线**（设计面地图 + nil=leave 与 clear 命令的表达缺口）→
  DECISIONS D5。
- R1 其余项原路由不变（MANIFEST §7）。
- O-38（CullingView transition obs）未动。

## 测试数字

- 定向：Sessions **6/0/0** · Library **742/4/0** · App **969/6/0**。
- zh-audit `--check`：**PASS**（2005 键、零孤儿、零缺 zh）。
- 全套 `--all`：**`TOTAL|4106/40/0|`（2209s，零 MEMFAIL）**，日志
  `all-runs/r12-round1.log`。bundle 向量：IOP 753/5/0（6782MB）· IOPParity
  478/6/0（5783MB）· Layers 494/5/0（817MB）· Library 742/4/0（630MB）·
  Sessions 285/9/0（1246MB）· Export 385/5/0（5348MB）· App 969/6/0（2832MB）。
  对账 = 4101 基线 + ΔN 5（SESS +1 CullingPipeline M-1 新法 / LIB +4
  LibraryMetadataWriterTests）逐值精确；skip 40 零漂移。

## 环境记录

- guard：构建前 PASS；全套前 G3 卡门（swap 6.6G 惰性冷页结构性高位，回落
  ~1MB/min 不可达）→ **临时校准 4G→7G 执行全套（DECISIONS D9），套后已复原**
  （工作区 tracked 零残留可证）。
- 构建容器：默认 DerivedData（Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi）就地重建
  （handoff 容器 = 同一容器，acc1/acc2 早已确认；本批必然重建）。
- `tuist generate` 恒为 Project.swift 改动后最后动作（L041）。
