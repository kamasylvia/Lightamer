# M2-9-02 ACCEPTANCE — ICC=DRT 强制联动渲染链（wave 2a）

**验收:** M2-9-02 独立验收 subagent（零共享上下文，实测核验）
**Date:** 2026-10-03 夜间（夜间全自动授权在案；`[gsd]` auto=true/paused=false 全程未动）
**输入:** PLAN（checker E7/E8 回注版）× SUMMARY × DECISIONS × LESSONS L053 × M2-9-01-ACCEPTANCE（基线 2611/16/0）× m2-6-drt 红线 × GOAL-STATE 续接点 × Alcedo 参考源与 .icc 资产（只读对表）× 全仓源码/测试实读 + 机检亲跑
**对象提交链:** `e87b25e`(T1) → `951d85c`(mluc 小修复) → `48a7136`(T2) → `ef3a70b`(T3) → `4ceee3b`(T4) → `8dcc32d`(收口)

## 结论

# PASS / 0 error + 1 minor + 2 observation

Plan 八条 AC 全部独立复核通过；全套独立复跑 **`TOTAL|2634/16/0|906s EXIT=0`**（`BFT_EXIT=0` 前置）与推算**精确对账**（2611 + 23，skip 16 保全）。1 minor = BUNDLE-MAP 增行 `ExportDrtChainTests` 记 **9**（T2 任务增量）而文件 method 终态 = **5**（DECISIONS §9 自己申报的 10/5/8 与行值自相矛盾）——验收批直接勘误（9→5 + 勘误注），doc-only 无回归面。两处平台关键主张（CalibratedRGB 死亡 → 自建 ICC v4、Alcedo 锚值「逐位一致」）经第一性原理重算逐位实证为真。

## 一、全套独立复跑（单轮全记录）

`caffeinate -dis xcodebuild build-for-testing`（`BFT_EXIT=0`）→ `caffeinate -dis Scripts/test-direct.sh --all`：

| Bundle | M2-9-01 终态 | 本轮 | Δ | 判定 |
|---|---|---|---|---|
| IOP | 467/1/0 | 467/1/0 | 0 | 零漂移 ✓ |
| IOPParity | 362/3/0 | 362/3/0 | 0 | ✓（01 波 minor 修复后基线保持） |
| Layers | 298/3/0 | **298/3/0** | 0 | 管线消费面门零漂移 ✓ |
| Library | 436/4/0 | 436/4/0 | 0 | ✓ |
| Sessions | 279/4/0 | 279/4/0 | 0 | ✓ |
| Export | 288/1/0 | **311/1/0** | +23 | = 10(DrtOutputColorSpace)+5(DrtChain)+8(DrtTailE2E) ✓ |
| App | 481/0/0 | 481/0/0 | 0 | ✓ |
| **TOTAL** | **2611/16/0** | **2634/16/0** | **+23** | **与推算精确对账** ✓ |

- peakRSS：IOP 6289 / IOPParity 5999 / Export 6244 MB——全部 < 8G 运行门，零 MEMFAIL。
- 新测试类逐类点名：Export 日志 23 条 `Test Case…passed`（三类合计）零 failed；display 零漂移门 **DrtTailTests 12 passed + AIMaskPlaneFormatTests 3 passed**（Layers 日志亲核）。
- 测试增量 23 vs front-matter 预估 25（-2）：DECISIONS §9 的复合方法组织（42 组合并入 2 法、断言数远超方法数）经实测认可——T1 的 `testEveryLegalCombosMatchesTheLinkageTable` 单法即覆盖 6×7 全域对表。

## 二、逐 commit 边界审计

| commit | 申报 | 实测 `--stat` | 判定 |
|---|---|---|---|
| `e87b25e` T1 | 映射 + 测试 + Project.swift + BUNDLE-MAP | 恰四文件（+787，全插入） | ✓ |
| `951d85c` 小修复 | mluc strOff 单行 | 单文件 1 行（20→28，ICC mluc 布局 = 类型头 16 + 记录 12，正解） | ✓ |
| `48a7136` T2 | builder/queue/renderer + 双测试 + Project.swift + BUNDLE-MAP | 恰七文件 | ✓ |
| `ef3a70b` T3 | PixelPipe/LayerCompositeDriver/ExportRenderer + E2E 增补 + BUNDLE-MAP | 恰五文件 | ✓ |
| `4ceee3b` T4 | yiyin E2E + BUNDLE-MAP | 恰两文件 | ✓ |
| `8dcc32d` 收口 | SUMMARY/DECISIONS/LESSONS/GOAL-STATE | 恰四文档 | ✓ |

`30d9bbf..HEAD` 生产面 name-status = **恰 front-matter 10 文件，零越界**；Tests 目录 = 恰 3 新文件**零既有改动**（AC1 diff 面 ✓）。

## 三、零 diff 红线机检（亲跑）

| 红线 | 机检 | 判定 |
|---|---|---|
| `ExportQuantizer.swift` | `git diff 30d9bbf..HEAD` = 0 行 | ✓ |
| `ExportQueueContract.swift` | 同上 = 0 行 | ✓ |
| `exportChain` 函数体 | ExportChainBuilder 全 diff **内容零 `-` 行**（两 hunk 全 additive：`Built.drtEncoding` 默认参载体 + `exportDrtChain` 新函数；`isLinearVariant` 零触碰） | ✓ |
| 队列引擎体 | ExportQueue 恰 4 hunks：Job 字段 / enqueue 增参+循环头 / Job init 透传 / execute TaskLocal wrapper——pump/cancel/retry/generation/concurrency 零触碰 | ✓ |
| 既有测试族 | 测试目录恰 3 A 记录、无 M 记录 | ✓ |

## 四、重点抽查（读码 + 第一性原理重算 + 实测）

1. **ICC 自建字节（DECISIONS §1 关键主张逐位实证）**：
   - `legalEOTFs` 镜像：DrtOutputColorSpace 8 legal 组合（rec709×{bt1886,gamma22} / p3d65×{gamma22,st2084} / p3d60,p3dci,xyz×gamma26 / rec2020×{st2084,hlg}）与 `DrtRecord.legalEOTFs(for:)`（:445-452）及 Alcedo `ResolveConfigProfileFileName`（cpp:76-118 实读）**三方逐行一致**；穷举 switch 无 default（`grep "default:"` = 0，6×7=42 组合全覆盖）。
   - **锚值重算**：以独立 Python 从 xy 色度 + Bradford→D50 第一性重算 rec709 矩阵，s15Fixed16 原码 `[28576, 14581, 912]` 与 Alcedo `rec709_bt1886.icc` 文件内 rXYZ **逐位一致**（g/b 六分量同样逐位）；p3_d60 臂 `[34485, 16168, -53]` 等九值与 `p3_d60_gamma26.icc` **全部逐位一致**——「逐位一致」主张属实（chad 两家推导路径略异属预期，矩阵面转换不消费它）。
   - TRC：curv count=1 u8Fixed8，563/614/666（2.2/2.4/2.6×256 四舍五入，DECISIONS 数字复算全真）；wtpt = D50 PCS 常量、header 128 字节 precondition 在案；mluc strOff=28 布局正确；时间戳固定 + 零 profile ID = 字节确定性（determinism 测试钉）。
   - Alcedo 资产实为 `para` fn=0 TRC（解析亲见）——本实现弃 para 走 curv 的平台规避与 L053② 一致。
2. **TaskLocal 递缝（DECISIONS §6）**：`ExportQueue` 并发锁 1（`ExportQueueContract.concurrency`，:10 注释 + :327 循环头亲核）⇒ `execute` 内 `$jobDrtTail.withValue(queued.drtTail)` 包裹单次 `renderLeg` await = **作用域恰 per-job**（无并发 job 隔离问题可言，结构即证）；`renderStage` 消费 `request.drtTail ?? Self.jobDrtTail`（显式字段优先）；detached-task 不继承语义由 queue E2E **像素 parity maxDiff==0** + profile 名恒等双断言实证（`testQueueDrtTailsCarrierDeliversToTheRender` 读码真）。
3. **尾格式覆写缝（AC6/checker E8）**：PixelPipe 恰 7 hunks（属性 / `.drt` 分支顶部 consult 一行 / runDrtTailLeg 传递〔DECISIONS §7 申报的第 4 hunk，不传则尾管道缝死——读码确认 `tailPixelFormat` 在尾管道上求值〕/ process 签名+赋值 / processComposite 签名+转发）+ Driver 恰 2 hunks（:204 签名 / :545 `terminalPipe.tailFormatFloatOverride` 直赋——该 pipe 不经 RenderPipeline 静态入口，E8 处方逐字兑现）；display 零漂移 = 默认 false + consult 仅 `isDrtTailLeg && .drt` 域内 + DrtTailTests 12/AIMask 3 零改全绿。
4. **exportDrtChain records verbatim（KD-2）**：`instances: source` 直传零预剔（builder diff 读码）；对比断言钉 legacy 剔 gamma vs DRT 保 verbatim（`testDrtChainCarriesRecordsVerbatim`）；降级单源 = pipe `isTerminalTailSkipped`（既有，零 diff）。E7 哑值面：`target = .sRGB` 座位 + `drtEncoding` 真载体 + 测试钉双侧；step 7 exit 腿 identity = **既有通用代码**（`coloroutOverridden ? exportTargetOverride : WorkingSpace` + `toSpace: exportTargetOverride`）零 diff 结构继承，同实例 identity 由 T1 缓存 + `testIdentityPassKeepsGrayThroughColorSync`（0.5 过 ColorSync ≤1e-6）钉。
5. **OQ-7/OQ-8 AC 落点**：OQ-7-A 强制联动 = `exportDrtChain`（装配切换 step 4）+ 输出 ICC = DRT 编码（E2E ICC 名断言 "Lightamer Rec709 Gamma 2.2" / "BT.2100" 亲核测试体）✓；OQ-8-A v1 钳位 = Quantizer 零 diff + `testHDRDrtExportClampsToUnitRangeThroughTIFFFloat32`（min≥0/max≤1/finite/非退化四断言）✓；TIFF 32f DRT 档 = 编码值 float32（DECISIONS §3 语义边界）由 full-precision off-lattice 断言钉 ✓。
6. **yiyin×DRT E2E（T4）**：断言结构真——HDR record 使 band/content 可分辨（SDR γ2.2 下编码白≡显示白不可分辨，换法理由 DECISIONS 在案成立）：band=post-EOTF 纯白（>250）vs 内容 PQ 码（<250）+ canvas ×2 宽 + ICC 仍 BT.2100 = **borders/watermark EOTF 后红线在导出腿实证**；sidecar 落盘（disk-truth）+ injector 走既有缝（`ExportYiyinInjector` 零 diff）。
7. **合成导出位深（E8 测试）**：`testCompositeTailFormatOverrideReachesTheDriverPlane` 经 `processComposite` + layerStack 实测 plane 位深（display bgra8 / override float32 双向断言）——checker E8 的 T3 补测试兑现。

## 五、AC 逐条（8/8）

| # | AC | 独立核验 | 判定 |
|---|---|---|---|
| 1 | 既有测试族零修改全绿 | Tests diff 恰 3 A；全套七 bundle 基线全数保持 + Export 311 全绿 | ✓ |
| 2 | Quantizer/Contract/exportChain 体零 diff | 三项机检亲跑（§三表） | ✓ |
| 3 | 穷举无 default + 非法 typed | grep=0 + 42 组合 accept-set==legalEOTFs 全域测试 + Alcedo cpp 对表 | ✓ |
| 4 | 四景出图（SDR/HDR/TIFF32f/yiyin） | E2E 四测试 + queue 递缝 parity 全绿（Export 日志逐条 passed） | ✓ |
| 5 | HDR 值域 [0,1] | min≥0/max≤1/finite/非退化断言读码 + 测试绿 | ✓ |
| 6 | 覆写缝四处 additive + display 零漂移 | PixelPipe 7 hunks + Driver 2 hunks 逐 hunk 核；DrtTail 12/AIMask 3 零改全绿 | ✓ |
| 7 | 队列引擎体零 diff，仅 additive 载体 | 恰 4 hunks 全载体；pump/cancel/retry/generation/concurrency 零触碰 | ✓ |
| 8 | Export 0 fail + 双登记闭环 | 311/1/0；Project.swift 3 行 + BUNDLE-MAP 3 行（9→5 勘误见 minor M-1） | ✓ |

**checker 回注兑现**：E7（ExportColorSpace 零加臂 + `.sRGB` 哑值 + `drtEncoding` 载体 + 哑值语义测试）✓；E8（Driver 第四处缝 + front-matter 登记 + 合成 layerStack 位深断言）✓。

## 六、minor 与 observation

- **M-1（minor，已修）**：BUNDLE-MAP 增行 `ExportDrtChainTests` = 9，而文件 method 终态 = 5（DECISIONS §9「10/5/8」与行值矛盾；9 = T2 任务增量误植行内）。验收批勘误 9→5 + 勘误注（全套 2634/16/0 与行合计复核实证）。doc-only，零回归面。
- **O-1（observation）**：`enqueue(drtTails:)` 等长约束 = `precondition`（崩溃面）而非 typed error——per-image 索引载体的编程契约，可辩护；M2-9-04 装配点（唯一生产 caller）接线时留意数组构造正确性。
- **O-2（observation）**：iCCP 重序列化（L053③）意味着**未来一切含自建 profile 的导出 golden 不得钉文件字节**——本波已把字节恒等断言收缩到系统 profile 面 + 纯函数层 copyICCData，范式正确；后续 phase 引用 L053 时按此口径。

## 七、翻账与提交

- **REQUIREMENTS**：M2EXP-04 追记「渲染链半边 Delivered（M2-9-02，验收本报告）」——不翻勾（元数据腿/命名腿归 M2-9-03、装配 UI 归 M2-9-04，条目完整交付后随 phase 收口勾选）。ALCE-02/03（V2 EXR/UltraHDR）本 plan 无可支撑增量（peak-ICC 边界 = DECISIONS §2 明确 V2 面），不动。
- **BUNDLE-MAP**：M-1 勘误（9→5 + 注）。
- **本验收批提交**：单 docs commit（本报告 + REQUIREMENTS 追记 + BUNDLE-MAP 勘误 + GOAL-STATE 续接点）。
- **不 push。**

## 八、下一步（交接 orchestrator）

C 档第 2 停 = M2-9-02 plan 闭环汇报（本报告为输入）→ 用户确认 → **M2-9-03**（元数据腿 + OMIT 剥离 + `resolveExportResolution` 切 renderStage sizing——checker E6 消费缝；消费本波交接的 `Built.drtEncoding`/`exportTargetOverride`/`ExportVariant.embedICC`）→ M2-9-04（App 装配点：`Request.drtTail` / `enqueue(drtTails:)` 双面注入 + `variant.drtOutput` 非 nil = 联动开关）。
