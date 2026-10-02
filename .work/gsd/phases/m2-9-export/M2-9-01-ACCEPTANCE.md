# M2-9-01 ACCEPTANCE — 数据模型与纯函数面（wave 1）

**验收:** M2-9-01 独立验收 subagent（零共享上下文，实测核验）
**Date:** 2026-10-02 夜间（夜间全自动授权在案）
**输入:** PLAN（checker 回注版）× SUMMARY × DECISIONS × M2-9-CHECKER × GOAL-STATE 续接点 × Alcedo 参考源（只读对表）× 全仓源码/测试实读
**对象提交链:** `6835bd2`(T1) → `3a1ecb8`(越界修复) → `e2a37f3`(T2) → `3b90709`(T3) → `ba379ac`(T4) → `f302011`(T5)

## 结论

# PASS / 0 error + 1 minor + 2 observation

Plan 九条 AC 全部独立复核通过；全套独立复跑 **`TOTAL|2611/16/0|939s EXIT=0`** 与推算精确对账（M2-8-3 基线 2577 + 新测试 34）。1 minor = 执行批越界修复 `3a1ecb8` **修复面不完整**（同根缺陷四处测试位只修一处，详见 §越界审计）——验收批独立复现并以同款测试侧修复闭环（`8e810a0`），修复后全套绿。缺陷不触及 plan 交付面（九 AC 与五 bundle 交付物全部干净）；SUMMARY「其余五 bundle 零预期漂移」的说法随该 minor 一并更正（见 §minor）。

## 一、全套独立复跑（三轮全记录）

| 轮 | 内容 | 结果 |
|---|---|---|
| 1 | `build-for-testing` exit 0 + `test-direct.sh --all` | **IOPParity 362/3/3**（`McpRenderParityTests` 三例 `functionNotFound("compositeLayer")`），脚本按 fail 即停于 829/4/3 → **发现执行批修复面缺口** |
| 2 | 验收批首版修复后重建 | build exit 65（`registerDefaultLibrary` 为 actor-isolated，同步 `setUpWithError` 调用非法——该轮全套跑在旧产物上，作废不计） |
| 3 | 改逐测试内联注册后重建 + 全套 | **`BFT_EXIT=0` + `TOTAL|2611/16/0|939s EXIT=0`**，MEMFAIL 零（峰值 IOP 7138MB / IOPParity 5999MB / Export 6505MB，全 < 8G 门） |

终轮逐 bundle 对账（vs M2-8-3 基线 + 本波增量）：

| Bundle | 基线 | 终轮 | Δ | 判定 |
|---|---|---|---|---|
| IOP | 467/1/0 | 467/1/0 | 0 | 零漂移 ✓ |
| IOPParity | 362/3/0 | 362/3/0 | 0 | 修复后回基线 ✓（首轮 3 fail 已消） |
| Layers | 298/3/0 | 298/3/0 | 0 | ✓ |
| Library | 436/4/0 | 436/4/0 | 0 | ✓ |
| Sessions | 279/4/0 | 279/4/0 | 0 | ✓ |
| Export | 260/1/0 | **288/1/0** | +28 | = 6(Settings)+11(Template)+5(Collision)+4(Metadata)+2(Recipe) ✓ |
| App | 475/0/0 | **481/0/0** | +6 | = 6(Store) ✓ |
| **TOTAL** | **2577/16/0** | **2611/16/0** | **+34** | **与推算精确对账** ✓ |

新测试方法逐一点名核对 = 34（DECISIONS §9 表逐行属实；T2 复合方法组织解释成立——11 法覆盖错误集全条 + 渲染锚 + sanitize 全族 + fallback，断言数远超方法数）。

## 二、逐 commit 边界审计

| commit | 申报 | 实测 `--stat` | 判定 |
|---|---|---|---|
| `6835bd2` T1 | settings/recipe/panelView/settingsTests 四文件 | 恰四文件（+534/−22）；PanelView 2 hunks 均补臂 | ✓ |
| `3a1ecb8` 越界 | QuickLookRendererTests 测试侧一行 | 单文件 +8（1 import + 1 注册 + 注释）；无产品码无夹具 | ✓ 申报属实（但修复面不完整，见 §四） |
| `e2a37f3` T2 | 模板引擎 + 测试 + Project.swift + BUNDLE-MAP | 恰四文件 | ✓ |
| `3b90709` T3 | Namer/Recipe/MetadataPolicy + 三测试 + Project.swift + BUNDLE-MAP | 恰八文件 | ✓ |
| `ba379ac` T4 | Store + 测试 + Project.swift + BUNDLE-MAP | 恰四文件 | ✓ |
| `f302011` T5 | SUMMARY/DECISIONS/GOAL-STATE | 恰三文档 | ✓ |

front-matter 15 文件全集命中、零未申报生产文件；执行偏差 D8（derivedTag/PanelView 补臂随 T1 落地保逐提交可构建）已在 DECISIONS §1 申报，front-matter 无越界。

## 三、重点抽查（读码 + Alcedo 正本对表）

1. **resolveExportResolution（KD-1）**：与 Alcedo `ScaleIntoBox`/`ApplyMaximumEdgeLimit`/`ResolveExportResolution`（cpp:31-80/287-325 实读）逐条同构——fit-inside min 正约束、`!allowUpscale` 钳 1.0、llround 取整 + [1, INT_MAX] 钳、cap 尾段全模式 + **DPI 宽度比修正**（Alcedo 对竖图同用宽度比，我方一致）、physical DPI≤0 typed 失败同文案语义、`dpi = spec.dpi_` 直通（不钳）。golden 手算逐值核对全真（2000×1333 / 2250×1500 竖约束 / 1800×1200 / mm-cm 换算 / **300×2/3=200 修正锚** / longEdge cap→150 / 钳与 no-op 边界）。
2. **targetSize 委托零漂移**：改造前版本逐行对照——三既有模式对新数学向量等价；**observation O-1**：取整由 `.rounded(.down)` 变 `.toNearestOrAwayFromZero`（llround）——KD-1 明文要求 llround（Alcedo 同），个别 .5 分数输入存在 ±1px 理论差，既有向量全绿、红线按「既有向量」口径成立，记 observation 不计缺陷。
3. **模板引擎（KD-3/OQ-4）**：11 token + literal 对 Alcedo `ParsePatternToken`/`PartText`/`FormatCaptureDate`/`SanitizeFileStem`（cpp:136-197/210-259 实读）逐形态一致——大小写不敏感、sequence 全零位宽、ISO 0 空、aperture/focal 1 位小数（POSIX 钉死小数点）、rating clamp 0-5、date 六 token + 默认 yyyyMMdd、sanitize 顺序（替换→剥尾→剥头→保留名→200 帽）一致；偏差 D3（shutter Double→有理数推导）/D4（date 字母白名单拒绝）均 plan 原文授权、DECISIONS 在案。`{{}}` 转义、`{}`/裸 `}` typed 错误、fallback "image" 测试钉全真。
4. **CollisionPolicy（OQ-5）**：4 参非 throwing 面体 = 旧体逐字搬运（唯一 diff = 局部变量提取 baseName，字符串同值）→ 默认路径逐字节；`.fail` 大小写不敏感占用 + typed `BaseNameOccupiedError`（携基名显示拼写）；`.replace` 永不落 `-N`；重载对形态（DECISIONS §6 D6）避免给三个不在 front-matter 的既有调用点强加 `try`——边界纪律执行正确。
5. **MetadataPolicy（OQ-6）**：mode + 6 bool 与 Alcedo hpp 字段清单一致（CONTEXT「7 bool」= 口语计数，DECISIONS §7 勘误成立）；STANDARD = 三 carrier 真 + 三剥离假；NONE 全假；`ExportVariant` 手写 `init(from:)` 三新键全 `decodeIfPresent` + 默认，encode 保持 synthesized（nil optional 不发射键）——两侧旧 payload 字面锚测试实测真（JSON 形状 = 旧 synthesized 发射）。
6. **NamingTemplateStore（OQ-9/KD-4）**：三内置 pattern 与 Alcedo `ExportNamingEditor.qml:37-40` **逐字节一致**（实读 QML 对表）；内置不入库（load/save 双侧 filter）；损坏 JSON/wrong-shape 降级空库；注入式 defaults（无 `.standard` 直读）；键 `export.namingTemplates` 源码常量钉死（AC7 grep 面）。
7. **字节不可达主张**：`metadataPolicy`/`embedICC`/`ExportCollisionPolicy`/`.physical(`/`.bounds(w:` 的 production 消费/构造点 grep = 声明文件外**零命中**——「既有调用路径字节不可达」成立。

## 四、越界审计（`3a1ecb8` 申报核验 + 验收批修复 `8e810a0`）

**申报三步归因核验：**
1. **活体夹具** ✓：`input/RAW/DSC00012.ARW.lra` 确为 gitignored（`.gitignore:19`）、现载 layerStack=1；mtime 10-02 21:50 与「试剥 layerStack 后从备份还原」申报时序吻合（申报的 00:52 写入点不可事后复验，但「带层活体」这一实质主张成立）。
2. **测试注册缺失** ✓：QuickLookRendererTests 全文件确无 IOP metallib 注册（修复前）；`registerDefaultLibrary(in:)` 为既有 API，全体 pipe 测试同款。
3. **stash 复现/重编不消**：过程性步骤无法事后独立复验，但结论与实测证据链自洽（归因正确）。

**minor M-1（修复面不完整）**：同根缺陷共有**四处**测试位（凡拷贝该活体 sidecar 且渲染腿未注册 IOP metallib 的测试），执行批只修了 Export bundle 首爆的 QuickLookRendererTests 一处——其 SUMMARY 明示全套对账移交验收批，但 DECISIONS §8「潜伏缺陷：任何带层 sidecar 必炸」的归因未推演到其它 bundle 的同夹具消费点，**IOPParity 的 McpRenderParityTests 三例**（parity plane / inline JPEG parity / render gate——testStalledRender 因先超时未到 kernel 派发而幸免；SC3 因自身已注册而幸免）在验收首轮全套复跑中实测炸出。**验收批处置**：同款测试侧修复（三处内联 `registerDefaultLibrary(in: PassthroughKernel.metalBundle)`，与本文件 SC3 先例及 `3a1ecb8` 同款；actor 边界要求在 async 测试体内 await）= `8e810a0`；无产品码、无夹具改动、零新测试方法（修复后三例本身即回归——撤注册即 functionNotFound 复现）。修复后全套 2611/16/0 绿。

**随 minor 更正**：SUMMARY 交接节「其余五 bundle 零触碰零预期漂移」对 IOPParity 不成立（漂移源 = 共享活体夹具，非本波代码）——执行批 T5 门按 plan 界定只含 Export/App 两 bundle，不算 AC 违约，但该表述以本节为准更正。

## 五、AC 逐条（9/9）

| # | AC | 独立核验 | 判定 |
|---|---|---|---|
| 1 | 四模式数学 golden | 六法全真 golden 手算复核 + bundle 绿 | ✓ |
| 2 | 旧 payload 解码兼容（Settings/Variant 两侧） | 两字面锚测试实测（形状 = 旧 synthesized 发射） | ✓ |
| 3 | 既有测试零漂移（E9 拆分口径） | NamerTests `git diff` = 空（亲跑）；Recipe/Settings 负行 = 0（append-only 亲跑）；向量全绿 | ✓ |
| 4 | 模板 12 字段/转义/错误/sanitize/fallback + shutter 形态 | 11 法覆盖全族 + Alcedo cpp:136-171 逐形态对表 + DECISIONS §3 | ✓ |
| 5 | 冲突三档（默认逐字节） | 5 法 + 重载同 URL 钉 + 旧体逐字搬运核实 | ✓ |
| 6 | 元数据默认 STANDARD 剥离三项 + 7 字段全量 | 4 法 + Alcedo hpp 对表 | ✓ |
| 7 | Store 三内置拼写 + CRUD + 键名 | QML:35-52 逐字节对表 + 6 法 + 键常量钉 | ✓ |
| 8 | 双登记 + 双 bundle 0 fail | Project.swift 4 行 + BUNDLE-MAP 4 行 + M2-9-01 注；288/1/0 + 481/0/0 | ✓ |
| 9 | 两枚举体零 diff + PanelView 仅补臂 | 3 hunks 全落 Variant(:49-116)/derivedTag(:197-207)，枚举体(:217/:366 起)零触碰；PanelView 2 hunks 全为不可达臂 | ✓ |

**checker 回注兑现**：E4（PanelView 入 front-matter + DECISIONS §1 五处清单）✓；E9（AC3 机检拆分）✓；E6（跨 plan 交接落 M2-9-03 T1 显式第 3 步 + golden 配套，实读 03-PLAN :176-193）✓；m1/m2 措辞/行号注 ✓。

## 六、observation

- **O-1**：`targetSize` 取整语义 floor→llround（KD-1 明文，Alcedo 同构）——非 .5 对齐输入无差；理论 ±1px 带记 DECISIONS §2（已在案），验收复核认可其「既有向量零漂移」口径。
- **O-2**：活体夹具漂移属反复现环境风险（gitignored、GUI 会话可随时重写）——本波两代修复（`3a1ecb8` + `8e810a0`）均测试侧注册；若后续再爆同签名，优先排查该 sidecar 的 layerStack 而非代码回归。

## 七、翻账与提交

- **REQUIREMENTS**：M2EXP-01/02/03 各追记「模型(数学/引擎)半边 Delivered（M2-9-01）」——不翻勾（消费面归 M2-9-02/03/04，条目完整交付后随 phase 收口勾选）。
- **本验收批提交**：`8e810a0` fix(m2-9-01) parity 注册 + 本报告 + GOAL-STATE 续接点 + REQUIREMENTS 追记（单 docs commit）。
- **不 push。**

## 八、下一步（交接 orchestrator）

C 档第 2 停 = M2-9-01 plan 闭环汇报（本报告为输入）→ 用户确认 → M2-9-02（DRT 强制联动渲染链；`ExportVariant.drtOutput` 载体消费 + E7 处方的新载体字段）。M2-9-03 接线时按 checker E6 处方消费 `resolveExportResolution` 修正 DPI。
