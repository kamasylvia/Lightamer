---
phase: M6-4
slug: gallery-stacks
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
---

# Phase M6-4 — Validation（图库 stacks + auto-stack + AI 分割蒙版原生 spike：双 plan 双路独立验收全 PASS 的闭环签核）

> 体例对齐 `phases/m6-3-ultrahdr/M6-3-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收
> （`dual_acceptance = true`）两 plan 各两路全部落终态后成文**：plan 01
> 双路 zcode 独立验收 PASS / 0 error + 0 minor open（第一路 5 登记 minor
> + 6 观察项 → 第二路零实质分歧 + N-1 升格建议，正本 =
> `M6-4-01-ACCEPTANCE.md` / `M6-4-01-ACCEPTANCE-2ND.md`）；plan 02 双路
> zcode 独立验收 PASS / 0 error + 0 minor open（第一路 4 观察项 + 第二路
> 5 观察 + N-1 升格建议，正本 = `M6-4-02-ACCEPTANCE.md` /
> `M6-4-02-ACCEPTANCE-2ND.md`）。omp 制度路**配额阻塞**由**第二支零共享
> 上下文 zcode 独立验收眼替代**（M6-2/M6-3 同款登记，晨审可裁）。两 plan
> 修批各一：01 = `984e0256`（Library 727→729：M-a ESCAPE 回归钉 + N-1
> autoStack 空池守卫 + M-c 两处悬空注记落账 + M-b/M-d/M-e 账本修复）；02 =
> `b49215bb`（App 814→816：N-1 livePlane 切层/切图身份比对释放 + 2 法
> 负验证亲跑——撤守卫恰两新法红）。**翻账只认证据**：SC 生效值对账正本 =
> 两 plan 各自 ACCEPTANCE×2 + SUMMARY + DECISIONS + CONTEXT（OQ-M6-4-1..7
> 全 A 夜间授权批）六份亲跑/亲读记录；charter 验收形态三件（ROADMAP M6-4
> 行）= stack 迁移 + round-trip ✓（V5Tests ①..⑧——v4 fixture 经**真迁移
> 槽 1→4** 构建 + 快照轮换亲证 + 幂等双跑 + futureSchema typed 拒）+
> auto-stack 聚类 golden ✓（ClusteringTests 8 法——preview 零写以**整包
> clean-close 前后字节恒等**强形态钉死 + 第二路 swiftc 直编九项边界独立
> 探针全过）+ spike 结论落档 ✓（SUMMARY §spike 五行判定表——机检判据全
> 绿、Describe 原生不可达按裁决⑦收口、GUI 轨 M-1..M-4 挂 Manual-Only
> 不静默）。**SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3841/24/0|` 两路
> 独立亲跑同值**（plan 02 验收批：第一路 2096s / 第二路 2097s，均 exit 0
> 零 MEMFAIL 零 crash；对账链 **3759 + 56 + 2 + 24 = 3841** 精确闭合：
> 01 修批前基线 3759 + LIB +56 = 3815〔01 双路亲跑同值〕→ 01 修批 +2 =
> 3817〔S8 重算基线〕→ 02 批 +24 = 3841〔02 双路亲跑同值，带
> 3838..3842 中心〕；skip 段和 1+3+4+4+4+4+4 = 24 = TOTAL 24 机械一致）。
> **02 修批后推算终值 = `3843/24/0`（对账带 3840..3844）**——3841 为实测、
> 3843 为修批 +2 推算，**两数并行申报不混淆**；全套 `--all` 于修批后未复
> 跑（批准制），**下一 phase 验收全套轮以 3843 为预期中心对账确认**（M6-5
> 修复后复跑轮在册，届时一并核销）。执行链：01 `f30e83a3..6fa1f536`
> （T1-T8 八 commit）+ 修批 `984e0256`；02 `86a0b292..cc1cb04f`（T1-T4 +
> T6 + T7 六 commit）+ 修批 `b49215bb`。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest。**plan 01 +58 法**（六新文件全 LIB，BUNDLE-MAP 六行亲对：LibrarySchemaV5Tests 8〔迁移四代 + 快照轮换 + 幂等 + UNIQUE 负测 + CASCADE〕/ LibraryStackStoreTests 16〔CRUD 全 op 族 + split 三边界 + 真钟 stamp〕/ AutoStackClusteringTests 8→9〔golden + gap 边界 + runs≥2 + 双 skip + preview 零写整包字节恒等；修批 +1 空池负测〕/ StackPaginationTests 9〔谓词双腿 + `.flat` 字节恒等 + fixup union golden〕/ ImportMergeStackTests 5→6〔四步匹配 + 零半栈；修批 +1 ESCAPE 回归钉——`%`/`_`/字面反斜杠三转义全走真 importFolder〕/ LibraryGridStackTests 10〔显示态 + fixup + 命令面〕）+ GridModelTests 既有 16 全绿（App 面零新法）；**plan 02 +26 法**（LAYERS 三新文件 +20：AIPatchAssemblyTests 9〔Planner 三 skip 门 + Composer ramp/帽/双分辨率 + KD-4 行 2 双数值门断言字面〕/ AIMaskFeatherTests 6〔golden 表 + 0 恒等双保险 + 单调性 + 负腿 logit-gain 三判据 + segmentPatch S6' 结构面〕/ PersonInstanceMaskTests 5〔四合成 label-buffer fixture + 真模型 black 场 noSubject 直启宿主实跑〕；APP 一新文件 +6：AIMaskPatchFlowTests 4→6〔debounce 合并 + 羽化 wire 字节级双写 + 修批切图/切层两法负验证〕） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠，L055 双保险两 plan 四路亲证） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3841 tests / 24 skip / 0 fail（实测，02 双路独立亲跑同值：第一路 2096s / 第二路 2097s，exit 0）**；七 bundle 逐行（02 第一路）：IOP **686/1/0**〔peak 7294MB〕/ IOPParity **460/3/0**〔6829MB〕/ Layers **494/4/0**〔1174MB〕/ Library **729/4/0**〔621MB〕/ Sessions **280/4/0** / Export **378/4/0**〔5554MB〕/ App **814/4/0**〔2832MB〕——peakRSS 全 <8G 运行门（最高 87%），零 MEMFAIL 零 crash，测试宿主 parentage = 脚本树（M2-7-3 纪律）；**修批后推算 3843/24/0（带 3840..3844），下一 phase 验收全套轮确认** |
| **基线演变** | 3759（M6-3 终值）→ 01 批 +56（LIB 六新文件 8+16+8+9+5+10，`func test` 亲点）= 3815〔01 双路独立亲跑同值 2134s/2121s〕→ 01 修批 +2 = **3817**（02 plan S8 重算基线）→ 02 批 +24（LAYERS 9+6+5 + APP 4）= **3841**〔02 双路独立亲跑同值〕→ 02 修批 +2 = **3843 推算**；对账链 3759+56+2+24+2 = 3843 精确闭合 |
| **SC 数字面** | 01：LIB 671→**729**（+56 批内 + 2 修批）/ APP 810 零漂移；02：LAYERS 474→**494**（+20）/ APP 810→**816**（+4 批内 + 2 修批）；IOP/IOPParity/Sessions/Export 四段两 plan 全程逐值零漂移；BUNDLE-MAP 十新行（01 六行全 LIB + 02 四行 LAYERS 3 + APP 1）与实测法数逐一相符（两路亲点） |
| **在案发现（本 phase 事件）** | **零 error 级发现**（两 plan 四路全 0E）；登记级 minor 五处全落 01 修批 `984e0256` 清偿（M-a ESCAPE 回归钉缺 / M-b 范围外两文件未申报 / M-c 两处悬空注记 / M-d D-12 清单漏数 5→7 / M-e 翻账推迟未编号——全部补登记或补测闭环）；升格建议两处均实修闭环（01 N-1 autoStack 空池守卫 `984e0256` / 02 N-1 livePlane 切层切图释放 `b49215bb`——**均带负验证亲跑：撤守卫恰新法红**）；观察项分账 = 挂账表六项（§挂账总汇编）+ 登记级若干（§特殊事项 §6） |
| **GUI 证据** | plan 01 UI 面由 GridStackTests 10 + App 810→816 机检承载（徽章/contextMenu/dialog/View 菜单，accessibilityIdentifier 已预埋）；plan 02 真机轮 = **Manual-Only**（layer B 资产需引导下载 + 真多人照片供件不可达，R4 授权条款行使合规——现场记录含人物模型 7s 四场实跑探针），配方 = `.work/gui-acceptance/m6-4/MANIFEST.md`（M-1..M-4 四行，**gitignored 本地证据**，D-10 申报）——挂账 #2 移交下一 GUI 批，不阻断收口 |
| **zh 对账** | 01 批 13 键尾块纯插入（diff 221 行全 `+`）+ 02 批 5 键尾块纯插入（`ai_mask_*` 族，86 行 `+`）——历史键字节/顺序零触碰；zh-audit `--check` 两路独立复跑 **PASS**（01：1677 source / 1918 catalog / zh complete；02：1682 / 1923 / zh complete）；UserDefaults **全 phase 零新增** |

---

## Plan 01 SC 生效值对照（`M6-4-CONTEXT.md` 裁决 D-M6-4-1..4，2026-10-14 夜间授权批全 A → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **schema v5 = 两新表 join 形态**（D-M6-4-1①）：`stacks` + `stack_content`（WITHOUT ROWID，PK (stack_id,image_id)）+ UNIQUE `idx_stack_content_image`（一图一栈 DB 级不变量 + stack_of 反查）；`images` 冻结列清单零触碰；封面 = position 0 成员单真相不设 cover 列 | T1 `f30e83a3` | **Delivered**：DDL 与裁决原式逐字节（双 CASCADE）；`schemaVersion = 5`；迁移槽 `from <= 4 && to >= 5` 三条 `CREATE IF NOT EXISTS` 幂等四代 + 快照轮换 `pre-migrate.4-5.bak` 亲证；`stacksColumns`/`stackContentColumns` 冻结面新立、`indexNames` 恰一行追加、`imagesColumns` 等既有冻结数组 diff 零命中（唯一命中 = 文档文字）；V5Tests ①..⑧ 全过——v4 fixture 经**真迁移槽**构建（诚实 fixture）+ 幂等双跑零重复 + 全腿 1→5 + futureSchema 6 typed 拒零写 |
| 2 | **auto-stack = LightCraft 全套语义**（D-M6-4-2①）：gap 默认 60s 用户可调 + preview 只报组数不动库 + capture 升序相邻 ≤gap 归簇 + runs ≥2 才成栈 + 跳过已堆叠/无 capture + 结果落 collapsed 普通栈 + 不存 auto 出处（无 undo 偏离登记） | T3 `80b7c5fd` | **Delivered**：StackClustering 纯函数（stable 排序 capture ASC + tie id ASC；≤gap 归簇；runs≥2；nil-capture 双重防御）+ `defaultGapSeconds = 60`；preview 零写以**整包 clean-close 前后字节恒等**强形态钉死 + 第二路 swiftc 直编九项边界独立探针全过（恰等归簇/链式合并/tie 序恒等/zero-gap/负 gap 全断）；store 腿 = per-cluster re-check（写腿 contended 重查）+ 已堆叠双 skip + **空池守卫**（修批 `984e0256` N-1——`IN ()` 非法 SQL 不可达 + 空池负测）；无 undo = D-04 登记在案 |
| 3 | **分页 × 堆叠 = 收起态 SQL 谓词 + 展开态页内 fixup**（D-M6-4-3①）：收起态纯 WHERE 谓词排除非封面成员（keyset seek 零改动、无滤片复制、runPage 唯一合法 diff 位）；展开态 App 侧 adjacency fixup（前拉 + 有界补拉 + displayed 去重，**forward-only** 偏离登记） | T4 `a33a24c1` + T6 `07d5fcdd` | **Delivered（D-01 语义收敛版）**：生效拼写 = **flag-aware JOIN**（KD-5 字面无 JOIN 式会隐藏**展开栈**的非封面成员——与 T4①/④ 测试规格直接矛盾，两路独立大库模拟反向亲证后裁决为准；D-M6-4-3 本体〔纯 WHERE/keyset 零改动/唯一 diff 位〕逐项保持）；`.flat` 缺省参 = SQL 字节恒等双证据（行级恒等测试 + 生产调用点 7 处清单，D-12 勘误版）；fixup forward-only（D-05）+ **union golden 跨页 fixture**（封面首页/成员后页双测钉无丢失）+ displayed-set 守卫；单栈展开 = 成员现 keyset 位不聚拢（D-02 v1，Lightroom 聚拢 V2）；收起态无首可见成员顶替 + overviewCount/groupCounts 口径分裂（D-06 登记，V2 候选） |
| 4 | **merge 产物自动成栈 = 导入缝**（D-M6-4-4①）：merge 族 provenance 三值 + sources 全解析到库内行 → `stackWith`（封面 + collapsed）一次性成栈；源不全 typed skip 零副作用；匹配细则与 skip 计数 plan 期定案 | T5 `c4ce7847` | **Delivered（D-07 版本化条款）**：白名单恰三值（`hdr-merge`/`hdr-merge-mertens`/`pano-merge`，focus-stack 排除）；四步匹配 = 后缀主式（批内 map 优先 → 全库 `LIKE '%' || ? ESCAPE '\'`，转义 `\`+`%`+`_`）→ 多命中 folderName 消歧 → 零命中 folderName/stem 兜底 → 整组 typed skip 零半栈；ESCAPE 语义两路独立探针亲证（sqlite3 `%`/`_`/字面反斜杠三转义 + 未转义对照臂证伪 wildcard 泄漏）+ 修批 `984e0256` 补 **M-a 回归钉**（ImportMergeStackTests ⑥）；link 模式不自动成栈（`Media/` 前缀门）；`mergeStacksCreated/Skipped` additive 双计数零 UI；五法全走真 importFolder（E1 硬门：禁手拼 image_path）+ D-10 批内隔离五独立导入批 |
| — | **AC7 零回归门** | T6/T7 + 四路机检 | **Delivered**：冻结面数组（imagesColumns/albumsColumns/albumContentColumns/versionRefColumns/reservedTableNames/triggerNames）diff 零命中；`.metal` 全域零 diff；Project.swift = 恰六行测试登记（dependencies 块零 diff，零新 SPM）；MCP 快照族（PhotoProjection/McpServerController）零 diff；`LightamerSidecar.swift` 零 diff（`.lra` 格式零字节变更）；V50Order 零触；UserDefaults 零新键；runModal = 0；新增 `String.LocalizationValue("` 插值禁形 = 0；xcstrings 13 键纯插入；既有族除 D-09 指名九处机械代际前滚（零语义变更零断言放松，两路逐行亲核）外原样绿 |
| — | **AC8 SC 数字门** | 双路终验批 | **Delivered**：LIB +56（六文件 8+16+8+9+5+10 亲点 ∈ 计划带 52..58 顶沿）/ APP +0；全套 **3815/24/0** 双路独立 build+run 同值（2134s/2121s）= 3759+56 精确；修批后 3817 = 02 plan S8 重算基线成立 |

## Plan 02 SC 生效值对照（裁决 D-M6-4-5..7 + KD-4 spike 五行判定 → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **hi-res patch 组装入 spike 判据 + 判据细则 plan 期定案**（D-M6-4-5①）：layer B `regionOfInterest` + quality 延迟重析 + patch 合成；零第二条装配 | T1 `86a0b292` + T2 `87efa887` | **Delivered**：`AIPatchAssembly`（Planner 三 skip 门〔空掩码/bbox>60% 全帧 Float64/min 侧 <32px〕+ pad 25% 短边 + 图界 clamp；Composer 界内精确值 + 界外逐字节恒等 + 接缝线性 ramp〔带宽 5% 短边 clamp 2..16〕+ ≤4 FIFO 帽）；`segmentPatch` = **恰一个委托表达式**（恒走 segmentSubject + `regionOfInterest` 传 patch 归一 rect + quality 钉 `.accurate`——S6' 结构面断言逐分量 1e-9）；KD-4 行 2 双数值门（0.6× 过渡宽 + ≤1px 缝错位）落断言字面（T6 `74a4709d`，双分辨率解析圆 fixture，D-08 并入不加方法）；debounce 单调度亲证（五连发 → 恰 1 run 末者胜） |
| 2 | **Edge 羽化 ±100 参数化顺带，零新 kernel**（D-M6-4-5②）：`MaskCombiner.blur` sigma 面已交付，纯应用层映射 | T2 `87efa887` + T4 `fbbcf449` | **Delivered（D-01 换锚正本，本 phase 最重项）**：sigma = \|p\|/100×0.02×longEdge（LightCraft 同式，正腿走既有 GPU `featherRadius` 缝——`.metal` 全域 diff = 0）；**负腿换锚 logit gain**——plan 草案 `1 − blur(1−x)` 经线性恒等式证伪（核和 1 的线性算子 L ⇒ `1−L(1−x) ≡ L(x)` 逐点恒等 = 与正腿同义不可能收缩），KD-3 自带「以 LightCraft 原文为准 + DECISIONS 申报」条款生效：`masks.rs` `gain = 1 − 7e` 施加于分割 logits → 落定 `x' = x^g/(x^g+(1−x)^g)`，g = 1−7·(percent/100)〔0.5 轮廓逐点不动 + 10-90 过渡宽 ≈g 倍收窄 + 端点精确〕；**双路独立数学推导 ACCEPT**（第二路 swiftinterface/FourCC 探针级亲证 D-03/D-04）；**双羽化防**（D-09）：resolveFeather 三臂 + `featherRadius` 显式参数仅 percent==0 穿透——两臂互斥数据流上不可达，wire 字节级双写钉死（正腿文件 == bake(σ) / 负腿 == bake(CPU 面, 0) / 0 == plain path 字节恒等） |
| 3 | **scribble 种子 = 本 phase 不激活**（D-M6-4-6①）：typed 拒缝保持现状，零激活工作 | 全批 | **Delivered**：本批 `.swift` 新增 diff scribble 命中 = 0（SUMMARY 文档文字除外）；`recordSeed` 的 `.scribble` typed 拒缝原样（diff 只增 patch 重置四行）；既有负测随 Layers 494/4/0 全绿；激活缝保持 = 零成本兑现 |
| 4 | **Describe = 挂账 V2，「原生不可达」收口**（D-M6-4-7①）：SAM CoreML 大件不启动（3.4GB Meta License 永不入仓 + 全族自转换）；Vision 零文本提示分割 API 实测 | RESEARCH B2 + T7 收口 | **Delivered**：RESEARCH B2 swiftinterface 全文 grep 实测（零文本分割 API；`VNStatefulRequest` = macOS 11 视频跟踪基类无关）——**第二路独立 grep 复核成立**（`Generate*` 请求族全列：saliency×2 + Foreground/Person InstanceMask + FeaturePrint + IterativeSegmentation，零 textprompt 面）；SUMMARY §spike 五行判定表 + V2 挂账五项在案；REQUIREMENTS 终态注记随本闭环批补齐（AC5 挂点 = D-12 翻账推迟，本批清偿） |
| — | **KD-4 行 4/5：人物实例 + spike 结论落档** | T3 `444f4047` + T5 | **Delivered（单测轨）**：`AIMaskSource.person`（"ai-person-" 前缀族，与 segment 重入门判别 disjoint 路由负测钉死）+ `detectPersonInstances` 直返 AIInstanceCatalog（零新类型，InstancePickerOverlay 零改复用，D-05）+ 提取恒标签合成（`labelComposite` 形参 = CVReadOnlyPixelBuffer，D-03）+ unionSelection 并集 + typed noSubject（零 all-ones 兜底扫描亲证）；四合成 label-buffer fixture 零 Vision 执行 + **真模型 black 场 noSubject 直启宿主实跑绿**；素场幻觉实况登记（white/gray128 → 1 实例，D-06——GUI M-3 判定须真无人像照片）；spike 结案语 = 机检判据全绿 + 不可达件按裁决⑦收口，**GUI 轨 M-1..M-4 挂 Manual-Only 不静默**（挂账 #2） |
| — | **AC7 零回归门** | T6 + 四路机检 | **Delivered**：`.metal` 全域 diff = 0；`generateScaledMask` 新增调用点 = 0（E2 双损坏禁用注记）；scribble 缝零扰；封存/冻结面（`RasterMaskStore`/`MaskCombiner`/`LightamerSidecar`/V50Order/NodeOwnershipCatalog/`SegmentEditingOverlayHost` host 零触）全零 diff；MCP 快照族零 diff；Project.swift = 恰四行测试登记（dependencies 零 diff，零新 SPM）；UserDefaults 零新键；runModal = 0；LocalizationValue 插值禁形 = 0；xcstrings 5 键纯插入；diff 文件全集 16 文件 ⊆ plan files_modified |
| — | **AC8 SC 数字门** | 双路终验批 | **Delivered**：LAYERS +20（9+6+5 亲点）/ APP +4 = 24 ∈ 计划带 21..25；全套 **3841/24/0** 双路独立 build+run 同值（2096s/2097s）= 3817+24 精确（带 3838..3842 中心）；修批 +2 = **3843 推算**（带 3840..3844） |

## 双重验收记录（dual_acceptance 链，两 plan 各两路）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **plan 01 第一路 zcode 独立验收**（2026-10-14 夜，零共享上下文） | **PASS / 0 error + 0 minor open + 5 登记 minor + 6 观察项** | 全套 `--all` 自建亲跑 **3815/24/0**（2134s）exit 0 + AC1-8 逐条 fresh evidence + 八 commit 逐 hunk 亲核 + 六新测试 56 法逐条对表 + 红线机检九项亲跑 + zh-audit 独立复跑 + sqlite3 ESCAPE 独立探针 | 五 minor 均登记级（实现面正确，缺断言/登记/清单精度）：M-a ESCAPE 回归钉缺 / M-b 范围外两文件 / M-c 悬空注记两处 / M-d D-12 清单漏数 / M-e 翻账推迟未编号——**全部 01 修批 `984e0256` 清偿** |
| **plan 01 第二路 zcode 独立眼**（零共享上下文；omp 制度位替代） | **PASS / 0 error + 0 minor open + 1 升格建议 + 4 独立观察** | 全套自跑 **3815/24/0**（2121s）与第一路逐值一致 + 六面独立审计自选切入（sqlite3 EXPLAIN QUERY PLAN / swiftc 直编聚类探针 / Python 200 行大库 keyset 模拟 / ESCAPE 三转义补强〔字面反斜杠面〕/ 13 键逐键 zh-en 提取 / D-01..D-12 逐项找 REJECT——零 REJECT）+ 第一路 5 minor 复核全部属实且清单完整 | **N-1 升格建议**（autoStack 读腿空池 `IN ()` 防御不对称——同函数 `stackedIDs(in:)` 有守卫）→ **采纳实修 `984e0256`**；N-2 申报措辞精度（EQP 实测 SCAN 但复杂度申报正确）/ N-3 格式键插值形态机检盲区 / N-4 补强记录 / N-5 link 行 source 候选——登记级；**与第一路零实质分歧**（N-1 定级差一档非分歧） |
| **plan 02 第一路 zcode 独立验收**（2026-10-15 夜） | **PASS / 0 error + 0 minor open + 4 观察项** | 全套 `--all` 自建亲跑 **3841/24/0**（2096s）exit 0 + AC1-8 逐条亲核 + **D-01 换锚深审 ACCEPT**（线性退化证明独立推导 + LightCraft `masks.rs`/`ai-masks.md` 原文亲读 + 落定式性质核 + 三判据测试钉面）+ 红线机检十项亲跑 + zh-audit 独立复跑 | O-1 在飞再 confirm 旧 base 重烘瞬态 / O-2 sigma 负 percent 对称映射表完备 / O-3 连续 Slider 中间值良定义 / O-4 person 单实例直烘与 layer A 先例同形——全部登记级恰当（第二路逐项复核维持） |
| **plan 02 第二路 zcode 独立眼**（零共享上下文；omp 制度位替代） | **PASS / 0 error + 0 minor open + 5 独立观察 + 1 升格建议** | 全套自跑 **3841/24/0**（2097s）逐位一致 + 五面独立审计（D-01 独立数学亲推不接受转述 / livePlane 生命周期三场景 / 异步竞态走查〔自环双门 + debounce + 残留 task 惰化〕/ 羽化双腿全量程 + 容差面 / KD-4 五行逐行独立核）+ D-01..D-12 找 REJECT 零 REJECT + D-03/D-04 探针级亲证 | **N-1 升格建议**（切层/切图不拆段会话——livePlane ≈400MB 跨图驻留 + 1s debounce 窗混合输入 patch 窄面）→ **采纳实修臂 `b49215bb`**（不采声明订正臂）；N-2 golden 表 12 行字面 vs 10 行实测 / N-3 `AIPatchRect` 钳制空域 precondition（产线不可达）/ N-4 seam band 截断一致性 / N-5 patch pass 每轮一条 history item 沿 07-3 语义——登记级；**与第一路零实质分歧** |
| **omp 制度路（两 plan 各一制度位）** | **配额阻塞登记（非 FAIL），未执行** | 制度位由第二支零共享上下文 zcode 独立眼替代（M6-2/M6-3 同款——omp 串行配额硬顶家族）；登记晨审可裁 | 不重试（lane_retry 语义）；如需可后补 omp 复核路，默认不需要——每 plan 双 zcode 独立眼意图已满足 |

四路终态：**零 error、零 open minor**（01 五登记 minor + 02 两升格建议全部修批
闭环，均带负验证或独立探针佐证）；两 plan 各自双路独立全套复跑同值互证
（3815/24/0、3841/24/0 逐值一致）——零实质分歧，dual_acceptance 意图满足。

## Per-Plan Map

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M6-4-01（面 A：图库 stacks + auto-stack） | T1 schema v5 两新表 + UNIQUE additive 迁移（KD-1）；T2 LibraryStore CRUD 全 op 族 + removeImage 解散清扫 + 一图一栈 DB 级（KD-2/KD-3）；T3 StackClustering 纯函数 + autoStack（KD-4）；T4 分页谓词/memberships/fixup 纯函数（KD-5 + D-01 flag-aware JOIN）；T5 导入缝 merge→stack 四步匹配（KD-6/E1 + D-07 条款）；T6 Grid 显示态 + forward-only fixup + 命令面（KD-7）；T7 徽章/contextMenu/AutoStackDialog/View 菜单/13 键（KD-8）；T8 收口 | worker 八提交 `f30e83a3..6fa1f536` + 修批 `984e0256`（M-a ESCAPE 钉 + N-1 空池守卫 + M-c 落账 + M-b/M-d/M-e 账本）；未 push | 双路 PASS / 0 error + 0 minor open（五登记 minor 修批清偿） |
| M6-4-02（面 B：AI 分割蒙版原生 spike） | T1 AIPatchAssembly（Planner/Composer + 9 法，KD-1）；T2 segmentPatch 薄委托 + AIMaskFeather（sigma + logit-gain 负腿 D-01 换锚 + 6 法）；T3 人物实例全脸（标签合成提取腿 E2 + `.person` 源族 + 菜单/picker 复用 + 5 键 + 5 法）；T4 commit 缝羽化接线（双羽化钉死）+ livePlane 捕获 + 1s debounce + runPatchRefine + toolbar 羽化节 + 4 法；T5 GUI MANIFEST（Manual-Only 降级，D-10，gitignored 无 commit）；T6 KD-4 行 2 数值门落断言 + 红线机检（`74a4709d`）；T7 收口 | worker 六提交 `86a0b292..cc1cb04f` + 修批 `b49215bb`（N-1 livePlane 切层/切图身份比对释放 + 2 法负验证 = D-13）；未 push | 双路 PASS / 0 error + 0 minor open（N-1 升格建议修批实修；四路观察项登记级） |

零红线域终态（两 plan 四路亲跑，`f498e5f5..b49215bb` 全程）：`.metal` 全域 =
**0 diff**（patch/羽化零新 kernel 传承兑现）；`Project.swift` = 恰十行测试登记
（01 六 + 02 四，dependencies 块零 diff，**零新 SPM**）；`.lra` sidecar schema
（`LightamerSidecar.swift`）= **0 diff**；MCP 快照族 = 0 diff；V50Order /
NodeOwnershipCatalog = 0 diff；UserDefaults = **0 新增**（全 phase）；runModal
= 0；LocalizationValue 插值禁形 = 0；xcstrings = 18 键尾块纯插入（13 + 5，
diff 全 `+`）；`generateScaledMask` 新增调用点 = 0；scribble 缝零扰；typed
noSubject 纪律（零 all-ones 兜底）扫描零命中。面 A 独有 = `images` 29 列冻结
清单零触碰 + `indexNames` 恰一行追加 + 既有 schema 测试九处机械代际前滚（零
语义变更）；面 B 独有 = 封存面（RasterMaskStore/MaskCombiner/
SegmentEditingOverlayHost）零 diff。Stacks 语义约定与 AI 蒙版缝约定见
AGENTS「M6-4 架构增量」节。

---

## 挂账总汇编（M6-4 单一移交清单，六项）

1. **栈顶被滤「首可见成员顶替」语义 → V2 候选**（01 DECISIONS D-06，KD-7
   登记义务已落账）：封面被 filter/语义腿滤掉时整栈从网格消失（纯谓词裁决的
   已登记代价），LightCraft arrange 语义腿 = App 侧可行（hit 集是有限 id
   表）；**同条并记** `overviewCount`/`groupCounts` 口径分裂（收起态 Overview
   总数按全量行、网格按封面行——stackMode 参数零调用点消费不实现）。两件
   同属 D-06，V2 语义腿批一并裁。
2. **GUI 轮 M-1..M-4 → Manual-Only 汇编，下一 GUI 批**：真图 patch 精修
   （M-1）/ 多人实例蒙版（M-2）/ 无人像 typed toast（M-3，**须真无人像照片
   ——素场幻觉探针已证 white/gray128 → 1 实例**）/ 羽化三档（M-4）+ plan 01
   侧徽章/dialog/菜单走查五行（`M6-4-01-ACCEPTANCE.md` §六）；layer B 资产
   引导下载为前置；配方 = `.work/gui-acceptance/m6-4/MANIFEST.md`（四行 +
   现场记录，gitignored 本地证据）；单测面已全绿，缺的仅人驱观感域。
3. **D-06（02）/ D-07（02）实测申报随 GUI 轮补录**：layer B ROI 产物分辨率
   实测值（组装面分辨率无关已由 2× fixture 钉死）→ 补录 `M6-4-02-DECISIONS
   §D-07`；person 标签编号域实测（起点/背景语义 vs layer A 出入）→ 补录
   `§D-06`。KD-1/KD-2 预留探针申报项，待供件 = M-1/M-2 走查现场。
4. **Describe 文本选择 → SAM CoreML 挂 V2**（charter 裁决⑦）：Vision
   macOS 27 零文本提示分割 API（swiftinterface 全扫两路独立复核）+ M2-10
   CLIP 图像级无像素掩码——原生无路；SAM 大件（3.4GB Meta License 永不入仓
   + ViT/DETR/CLIP 全族自转换）不在本 phase 启动；ModelAssetStore 安装链 +
   AIWorkerProtocol 第四腿已备，用户裁 SAM 立项 = 另开独立 phase。
5. **livePlane 残差两笔（D-13 申报，登记级）**：①切图发生在末次 pass 完成
   之后且无 pending debounce 时平面驻留至其余释放点（模式退出/新 seed/下一
   次 wire 活动——窄面：segment 模式跨图滞留且不再交互；eager 释放需
   EditorState→LayerEditingState 新横 wire，超小修臂量级不做）；②confirm
   生成**在飞中**切图 = O-1 同族在飞竞态（旧 base 重烘一次，同主体域收敛可
   undo，V2 若做「patch pass 互斥锁」可消）。D-13 主修（stamp + fire 身份
   比对 + schedule 缝前置同判）已闭环 `b49215bb`。
6. **M6-1 挂账四项清偿进度核查（本批读账）**：①Manual-Only C 行终端目测
   （无头 connect 指引）——M6-2..M6-4 零 MCP 面触碰，未顺带清偿；②孤儿
   fixture `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 挂账 #6
   延续）——01 验收 O-vi 复登记在案、工作树仍 untracked，未清偿；③legacy
   只读回退面缺席——未触碰；④move 窗口锁短暂释放 + probe TOCTOU 观察项——
   未触碰。**四项均未被顺带清偿，全额转 M6-5 清算批**（M6-2 三项 + M6-3
   五项挂账同批累加，M6-5 清单 = M5 三汇编 + M6-1 四项 + M6-2 三项 + M6-3
   五项 + M6-4 六项）。

另有**登记级观察**不占挂账（四路在案，零动作或顺目）：fixup 共享 anchor 插入
序（O-ii）/ fixup 前拉成员徽章 map 下次 reload 自愈（O-iii）/ 展开态 chevron
翻转无可见变化 D-02 观感（O-v）/ EQP 机制名申报精度（01 N-2，复杂度正确）/
格式键插值形态机检盲区（01 N-3——后续机检补 `String(localized: "…\(` 非格式
键形态检查候选）/ link 行 source 候选（01 N-5，混合导入极边缘 V2）/ 在飞
patch 竞态与 sigma 表完备等 02 O-1..O-4 / golden 表行数记账（02 N-2）/
`AIPatchRect` 钳制空域产线不可达（02 N-3）/ seam band 截断一致性（02 N-4）/
patch pass undo 步积累沿 07-3 语义（02 N-5）。

**批内已清偿**不占挂账：01 五登记 minor（M-a..M-e → 修批 `984e0256`）+ 02
N-1（livePlane 切层/切图释放 → 修批 `b49215bb`，负验证亲跑）+ AC5 的
REQUIREMENTS 注记推迟（D-12/D-15 申报位 → 本闭环批翻账清偿）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。七项 OQ 生效值（D-M6-4-1..7）+ 两
  plan 各 AC7/AC8 + KD-4 spike 五行判定每条均有 ≥1 机器锚（01：58 法六新
  文件〔迁移四代 + CRUD 全 op + 聚类 golden + 谓词/fixup + 导入四步 + 修批
  ESCAPE 钉与空池负测〕/ 02：26 法四新文件〔三 skip 门 + 双数值门断言字面 +
  羽化三判据 + wire 字节级双写 + 四 fixture + 真模型 black 场实跑 + 修批
  切层切图两法〕）+ ≥1 实证背书（两 plan 双路独立全套亲跑同值 3815/3841 +
  对账链 3759+56+2+24+2 = 3843 精确 + D-01 换锚双路独立数学推导 + LightCraft
  原文亲读 + swiftinterface 独立 grep 复核 + sqlite3 EXPLAIN/ESCAPE 独立探针
  + swiftc 直编聚类九项边界探针 + Python 大库 keyset 模拟 + BUNDLE-MAP 法数
  亲点 + zh-audit 两路独立复跑 PASS）。
- 采样密度：两 plan 全 AC 逐条机检（84 新测 + 既有面零回归双保险：六 bundle
  逐值零漂移 + 冻结/封存面零 diff 机检族）+ **每 plan 双路零共享上下文独立
  验收**（各自自建 build + 各自全套 `--all` 亲跑，第二路证据亲跑/亲读重取
  不复述第一路）+ checker FAIL 先审后放（plan 评审 2E+7M 回注 `556d83fb` →
  修订版 `d1a87117` → checker 放行 `8198f3be` 三步链在案）+ 修批均带负验证
  或独立探针；「无证据 ✅」零项。
- 数字对账：两 plan 各双路互证（3815/24/0 与 3841/24/0 各两轮独立亲跑逐值
  一致 + 段级 skip 和 = TOTAL 机械一致 + 对账链五段精确 + LIB/LAYERS/APP
  增量与文件 grep 亲数一致）；**3841（实测）与 3843（修批后推算）并行申报
  分账清晰**。

## 特殊事项入册（phase 级事件台账）

1. **omp 制度路配额阻塞 → 双 zcode 独立眼替代**：原制度第二路（omp 串行）
   两 plan 均因配额硬顶阻塞（M6-2/M6-3 同款 429 家族），第二路意图由第二支
   零共享上下文 zcode 独立验收眼兑现（两 plan 均 PASS，全套独立亲跑同值）
   ——**dual_acceptance 意图满足、制度字面偏离**（omp 未参与本 phase 验收），
   登记晨审可裁。
2. **D-01 换锚（plan 02，本 phase 最重裁决行使）**：plan KD-3 草案羽化负腿
   公式 `1 − blur(1−x)`（形态学腐蚀的高斯近似）经线性恒等式证伪——核和 1
   的线性算子 L 下 `1−L(1−x) ≡ L(x)` 逐点恒等，与正腿完全同义不可能收缩；
   KD-3 自带「执行期先读本地 LightCraft checkout 核对符号语义，有出入以
   LightCraft 原文为准 + DECISIONS 申报」条款生效 → 负腿换锚平面域 logit
   gain（`masks.rs` `gain = 1 − 7e` 施加于分割 logits 的诚实平面等价，g 上限
   8 = 原文 8×）；**两路独立数学推导均 ACCEPT**（文件名/函数名/缝结构照
   plan 钉死形不变）。程序合法 + 数学正确双锚，晨审推翻路径 = DECISIONS
   §D-01 三判据测试面回退。
3. **数字口径纪律（3841 实测 / 3843 推算并行申报）**：全套 `--all` 终验实测
   = 3841/24/0（02 双路独立亲跑同值）；02 修批 +2 后推算终值 = 3843/24/0
   （对账带 3840..3844）。修批后全套未复跑（批准制 + M6-5 复跑轮在册）——
   下一 phase 验收全套轮以 3843 为预期中心确认，**两数不得混写**。
4. **修批闭环形态（先例沉淀）**：两修批的升格建议实修均带**负验证亲跑**
   （撤守卫恰新法红、既有法不咬 → 回补复绿）——02 修批负验证（D-13）为
   该形态首次成文申报；后续验收批修批沿用。
5. **T5 Manual-Only 降级合规（plan 02）**：layer B 资产需引导下载 + 真多人
   照片供件不可达（R4 授权条款），MANIFEST 落现场记录（含人物模型 7s 四场
   实跑探针证据）+ 四行配方交 GUI 批；**该目录 gitignored → T5 commit 空转**
   （D-10 显式申报，非静默——历史各批 MANIFEST 同为本地证据惯例）。
6. **登记级观察聚拢**（见挂账节末，两 plan 四路在案）：零代码面零用户可见
   面者不立账；其中 01 N-3（格式键插值形态机检盲区）与 01 N-2（EQP 机制名
   申报精度）为流程改进候选，M6-5 清算批可顺带评估机检 grep 硬化。
7. **环境事件两笔（02 D-11，非产物缺陷）**：AIWorkerClientTests 首轮一次性
   挂起（worker respawn 时序，单类 + 全套双复跑绿证非稳定缺陷）；死代理 env
   撞 SPM re-resolve → `env -u` 旁路 runbook 入 LESSONS L080。

## 授权记录（C 档第 3 停 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6-1..M6-3 全系 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（research/plan/
  执行 + 双重验收编排 + 修批 + 本 VALIDATION 同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`.work/
  config.toml [gsd] paused=false / auto=true` 全程未动，dual_acceptance=true
  在册）；用户晨审可推翻本签核（推翻 = M6-4 签核作废回退，已交付面与四路
  执行/验收证据不受影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION 成文 executor（2026-10-16 闭环批）；
  **doc-only——零源码 diff**（`git status` 对表 = 本批全 docs + 四份 ACCEPTANCE
  入库；工作树既有 untracked 兄弟批/孤儿 fixture 件〔M3-1-ACCEPTANCE-PI /
  retro-dual / dt-clone-archive / srgb-matrix-8.tif.lra = M4-1 #6〕本批零
  触碰）。
- **呈报裁决点（禁静默）**：①GUI 轮 M-1..M-4 安排（挂账 #2，默认 = 下一
  GUI 批汇编，layer B 资产下载前置）；②栈顶顶替 + 计数口径 V2 语义腿立项
  时机（挂账 #1，默认 = V2 候选不动）；③Describe→SAM CoreML V2 是否立项
  （挂账 #4，charter「大件另裁」——用户专属）；④livePlane eager 释放残差
  是否值得新横 wire（挂账 #5，默认登记不动作）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：M6INT-02 / M6INT-03 翻 **Delivered（validated）**——面 A
  stacks 全套终态 + 面 B spike 五行判定终态（Describe 不可达收口 + V2 挂账
  注记）。
- ROADMAP：M6-4 行 ✅ 闭环（两 plan 双路结论 + 修批链 + 3841 实测/3843 推算
  并行申报）；头部 Milestone 6 行追加 M6-4 closed。
- STATE：M6-4 complete + current_phase 翻新 = next M6-5；m6_phases_complete
  5；M6 Ledger 5/7。
- TODO：M6-4 条目落账（[x]）+ M6 头部翻新（M6-4 ✅ 闭环，下一步 = M6-5）+
  M6-5 清算清单追加 M6-4 挂账六项。
- GOAL-STATE：续接点翻新 = **M6-4 closed → M6-5（挂账清算批）**；LightCraft
  裁决⑤（stacks + auto-stack 优先）已由 M6-4-01 兑现、④（AI spike）已由
  M6-4-02 兑现——charter 剩余项 = M6-5 清算 + M6-6 FEATURE-MAP + M6
  VALIDATION 收口（smart albums 次之 / 挑片视图 / watched folders = 裁决⑤
  范围红线不立项挂账）。
- 修批 `984e0256` / `b49215bb` 已在库；未 push；测试宿主/GUI 进程零残留（四
  路验收批各自清场申报在案）。

## 签核

- 七项 OQ 生效值（D-M6-4-1..7）+ 两 plan AC7 + AC8 + KD-4 spike 五行判定
  全项 **Delivered**（三列证据齐；数字对账 = 01 双路 3815/24/0 + 02 双路
  3841/24/0 独立亲证，对账链 3759+56+2+24+2 = 3843 精确闭合；双重验收每
  plan 零实质分歧）。
- `status: validated` + `nyquist_compliant: true`。
- **M6-4（图库 stacks + auto-stack + AI 分割蒙版原生 spike）closed**：两
  plan 双路独立验收 PASS / 0 error + 0 minor open（登记 minor 与升格建议
  全部修批闭环），终验全套实测 `TOTAL|3841/24/0|`（02 双路 2096s/2097s）+
  修批后推算 `3843/24/0`（带 3840..3844，下一 phase 验收全套轮确认）；挂账
  单一清单六项（栈顶顶替 V2 候选 / GUI 轮 M-1..M-4 Manual-Only / D-06·D-07
  实测补录 / Describe→SAM V2 / livePlane 残差两笔登记 / M6-1 四项核查未清
  偿转 M6-5），移交 M6-5 清算批与晨审。
- 晨审裁决项：四项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
