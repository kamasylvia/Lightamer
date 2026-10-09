# M2-5-ACCEPTANCE-OMP — 「调色」回溯二次验收报告（omp 独立）

> 验收批：2026-10-09（omp 二次验收，零共享上下文）。对象 = M2-5 phase 三 plans（M2-5-1 Grade 新件核 / M2-5-2 Look/Tone 面板重组 + 默认 look / M2-5-3 LUT 三件套 + 收口）。正本亲读：三 ACCEPTANCE + 三 SUMMARY + 根 AGENTS.md「M2-5 架构增量」节 + `evidence/spectral-film-lut-license.md`。方式 = file:line 读码 + git 机检 + 许可链亲测 + 定向双类复跑（禁 `--all`）。注意：工作树已演进至 M3-4 后（HEAD `81b5df5`），M2-5 交付经 squash `747296f` 入主干；凡 M2-5 后演进造成的现状差异（如 18→19 行）逐处标明，不记 M2-5 账。

## 结论头

**PASS / 0 error + 1 minor**

- 三 plan 首验 PASS 结论全部复核成立；抽查点 1–5 逐项亲证，无实质分歧。
- 唯一新发现 = M2-5-1 注释异字（minor，未修——只读纪律），零语义影响。
- 定向复跑：GradeCatalogTests 15/0/0 + LutLibraryRecursionTests 16/1/0，0 fail。

## 逐 plan 判定

### M2-5-1 Grade 新件核 — PASS

- 首验称 PASS / 0 error + 2 minor（已修）+ 1 observation：Tint 归因修正、E7 闭合测试补齐、BUNDLE-MAP 计数勘误三处均在现状可验证（E7 测试 `testAllCatalogOpsAreDefaultFaceRegistered` 在册，见定向类方法清单）。
- GradeCatalog 现状 19 行 = M2-5-18 行 + M3-3-02 `filmPlacement` 第 19 行（`NodeOwnershipCatalog.swift:263-266` 注释明载扩展）；前 18 行顺序与首验 ledger 一致，M2-5 交付面成立。
- V50Order 十行终位与 SUMMARY 表逐位一致（见抽查点 1）；add-only 经 squash 后无法逐 hunk 复演 M2-5-1 原 commit，但行注释逐行载明 M2-5-1 来源且 dt verbatim 行零扰动（28.5 簇/singleton 结构完整）。

### M2-5-2 Look/Tone 面板重组 + 默认 look — PASS

- 首验称 PASS / 0 error + 1 minor（strength clamp 已修）：`cdlDelta` clamp 为 tone 面板语义，本批抽查范围未覆盖面板读码（任务书抽查点无面板项），但 `defaultLook` 单源（`NodeOwnershipCatalog.swift:286-296`，+1.5/+15/1.3）与 DefaultLookTests 五法所钉之值同源，mint 消费面存在。
- `.lalb` v1→v2 首迁与 TAB-MATRIX 行账属首验已闭环项；现状 schema 已继续演进（v3 version_ref），属 M2-5 后演进，不复核。
- 本 plan 无任务书抽查点直指项，判定 = 首验结论无反证 + defaultLook 单源亲证。

### M2-5-3 LUT 三件套 + 收口 — PASS

- 首验称 PASS / 0 error + 2 minor（文档勘误已修）+ 2 observation：AC-8 区间勘误注记在 SUMMARY:85 可见，F2 seeder 勘误注记在 SUMMARY:112-118 可见，两处勘误均已落盘。
- 许可门（最重项）本批独立重验全部成立，见抽查点 3。
- recursion/键升级/可配根/seeder 四机制读码亲证，见抽查点 2/5；`LutLibraryRecursionTests` 16 法定向 16/1/0。

## 逐抽查点证据

### 1. GradeCatalog + V50Order + ACEScc envelope（读码）

- **18 目录五元组 + defaultLook 单源**：`LightamerIOP/Sources/NodeOwnershipCatalog.swift:172-267` 行表（M2-5 时态前 18 行：cat02WhiteBalance/exposure/contrast/white/black/shadows/highlights/curve/hls/saturation/vibrance/colorWheel/lmt/tint/clarity/sharpen/halation/filmGrain，第 19 行 filmPlacement 为 M3-3-02 扩展）；五元组 = catalogID/opName 常量/owner/identityJSON（各模块 Params 自编码，checker m5）/panelExposures；`defaultLook` 三 entry `NodeOwnershipCatalog.swift:286-296`（+1.5/+15/1.3）为唯一默认 look 来源。✅
- **V50Order add-only + 七新件位**：`LightamerCore/Sources/Foundation/V50Order.swift:61` acesccIn 20.5 < exposure 21.0；`colorWheels` 41.0（:128，与未注册 dt colorbalance 同位 = 声明例外）、`cat02WhiteBalance` 41.4（:132）、`contrast` 41.6（:137）、`white` 41.8（:142）、`black` 41.95（:145，KD-3 ±0.05 挪位注记）、`saturation` 42.2 / `tint` 42.4 / `hls` 42.6（:152-154）、acesccOut 69.9（:219）；七新件全部落在 v50 RGB 段 `colorbalance 41.0`–`rgblevels 43.0` 空位，与 SUMMARY 七件终位表逐位一致。✅
- **envelope 走 LayerCompositeSeam + ≥1 目录 op 包夹**：`LightamerIOP/Sources/ACEScc/ACESccInModule.swift:126-128` `needsEnvelope` = `GradeCatalog.item(opName:)` 查询面（非白名单散抄）；:132-137 `wrap` 首尾包夹；:141-143 `install()` 注入 `LayerCompositeSeam.acesccEnvelope`（Core 不可 import IOP 的合法缝）。✅
- minor：`ACESccInModule.swift:118` 注释含异字「`boxes and铸 a fresh`」（M2-5-1 T2 commit `764e187` 原生，首验未提；注释零语义影响，未修）。

### 2. LutLibraryStore 键升级 + shared holder + 切根（读码）

- **键 = 根相对 POSIX 路径**：`LutLibraryStore.swift:189-190` `installed`/`parsed` 字典键；`adopt` 以 relativePath 为键（:329-330）；根下文件 relativePath == 文件名（:320-322，旧行语义退化）。✅
- **旧档 fallback**：`resolvedKey(for:)`（:367-377）= 精确命中 → 唯一尾段匹配 → 歧义 nil（三段完整）；`lut(named:)` nil = 缺席（:413-418），`displayKey` 供面板高亮不改字节（:392-397 + 注释 :391）；lut3d 缺席走 blit identity（`Lut3dModule.swift:23-29` L031 红线注记）。✅
- **shared holder**：`private static var sharedInstance` + NSLock（:105-106）+ 锁内读 getter（:112-116）+ `replaceShared(_:)` 原子换（:121-125）+ `SharedForwardingResolver` 长寿命转发（:132-138）；Registry 注册行走 `sharedResolver`（`Registry.swift:405-407`），`Lut3dModule` 自身 M2-5-3 零 diff（首验复核 + 现状注册行注释 :399-404 佐证）。✅
- **切根 validateRoot**：`validateRoot`（:158-166）= isDirectory 守卫 + 写探针（`.lightamer-lut-probe-<uuid>` 即建即删）+ 无 bookmark（注释 :156-157 明载）；坏根不持久化由 Settings `applyLutRoot` 前置承载（首验 AC-5 已核，本批未重读 Settings 面——任务书只要求 validateRoot 本体）。✅
- **递归收录**：`rescan()` 用 `enumerator(at:)` + `skipsHiddenFiles`（:267-270），`registry.json` 天然不过 `.cube` 扩展过滤（:275）。✅

### 3. 许可红线（亲测）

- **数量对表**：`Resources/LUTs/` = 42 项（40 `.cube` + LICENSE + NOTICE，`ls` 实测）；evidence §四对照表 41 行 − #40 不造 + #33 上游名收编 = 40，逐名抽查首尾（Agfa_Vista_100 … Kodak_Ultramax_400 … Kodak_Vision_320T_5277）与对照表「生成文件」列一致。✅
- **零 Alcedo 字节**：40/40 全 `LUT_3D_SIZE 65`（逐文件 grep 机检零脱漏）；抽 3 张 TITLE = 裸 stock 名（`TITLE "Kodak_Portra_400"` / `"Fuji_C200"` / `"Kodak_5222"`），与 evidence 取证的 Alcedo Windows 路径形态（`D:\Projects\...`）字节形态不同；`D:\Projects` 字符串在 40 张内零命中；`alcedo` 大小写不敏感全包唯一命中 = NOTICE 内「no bytes were copied from Alcedo Studio」声明句本身。BW 表（Kodak_5222）RGB 三列相等灰度特征在位。✅
- **LICENSE/NOTICE 随包**：LICENSE 头 = `MIT License / Copyright (c) 2026 Jan Lohse`（与 evidence §二摘录逐字一致）；NOTICE 载上游 URL + v0.18.2 + SHA `42f4f3f…ce5f` + 两偏差（65/BW 配 2302）+ 零 GPL 声明。✅
- **证据文件**：`evidence/spectral-film-lut-license.md` + `spectral-film-lut-generation-log.json` 在位（10KB/13KB，2026-10-01）。首验已用 GitHub API 独立重查 tag/SHA/MIT 三点（M2-5-3-ACCEPTANCE §许可门 #1-3），本批未重复打 API（网络动作非必要——包内字节 + 首验 API 记录双证据已闭环）。✅

### 4. 定向测试（亲跑，禁全套遵守）

- `--bundle App GradeCatalogTests` → `BUNDLE|App|15/0/0|peakRSS=195MB|3s` EXIT=0。15 法 = 14（M2-5-1 首验终值，含 E7 闭合）+ 1（M3-3-02 m8 闭合扩展法；方法名仍含 Eighteen/Fourteen 字面但断言 19/15——M3-3 改值未改名，见 observation）。0 fail。✅
- `--bundle IOPParity LutLibraryRecursionTests` → `BUNDLE|IOPParity|16/1/0|peakRSS=464MB|51s` EXIT=0。16 法清单逐一 M2-5-3 语义（递归/隐藏跳过/迁移/fallback/歧义/切根/坏根/seeder 两法）；1 skip = 万文件探针环境门控（与首验 16/1/0 逐值一致）。0 fail。✅
- BUNDLE-MAP 对账：`APP 15 GradeCatalogTests.swift`（:225）/ `IOPP 16 LutLibraryRecursionTests.swift`（:103）与复跑计数精确一致。✅

### 5. seeder + 键拼写机检（git/代码）

- **folderReference**：`Project.swift:179` `.folderReference(path: "Resources/LUTs")` + 注释 :170-175（glob 会拍平 40 表；Tuist 4.208 裸目录串静默忽略）；vendor commit `509eb56`（M2-5-3 T5，Sep 30 23:25）body 载 42 项落包验证。✅
- **键单源**：`"lut.library.root"` 字面全仓唯一命中 = `LutLibraryStore.swift:145` 常量定义；消费点 `LutLibraryStore.swift:196`（init 直读）+ `AppPreferences.swift:48`（re-export 常量）+ `SettingsPagesTests.swift:234`（拼写断言），零第二字面。✅
- **入盘形态**：M2-5 经 squash `747296f`（Oct 7）入主干，96 files / +10994401（含 40 表 314MB）；`509eb56`/`a34bb03`（键升级）/`cfe4187`（可配根）/`769d37a`（面板树）/`e7f919a`（许可 evidence）执行链可考。✅

## 与首验分歧点

- **实质分歧：无**。三 plan PASS 结论、测试计数链（2287→2305→2327）、许可门 MIT 结论、键语义申报，本批亲证全部成立。
- **口径注记（非分歧）**：
  1. 首验三报告所记执行 commit SHA（`ba70717`/`d584835`/`a31ac15` 系）为 squash 前执行分支形态，主干现仅存 squash `747296f` + 独立 docs/vendor commits；逐 commit diff 复演不可行，本批改以现状 file:line + 行注释来源注记 + 测试钉死为据——证据效力等价。
  2. GradeCatalogTests 两方法名（`...Eighteen...`/`...Fourteen...`）与现断言 19/15 名实不符——M3-3-02 改值未改名，M2-5 范围外演进，首验时态下名实相符。不记 M2-5 缺陷，仅 observation。
  3. 首验 M2-5-3 F2（测试触真实用户目录）与 O1（rescan 314MB I/O）为遗留观察项，本批未复测——属后续 phase 改善挂账，非 M2-5 验收条件。

## 会话卫生

- 只读遵守：除本报告文件外零写入；`git status` 未新增修改（预存 `M OMP-RETRO-QUEUE.md` + 两个兄弟 OMP 报告 untracked 为他批产物，未触碰）；不 push。
- 测试纪律：仅两定向类；一次误敲 `test-direct.sh --help`（脚本无此参数，被解析为类过滤）即刻 kill（bg_6），未形成全套运行；测试宿主进程零残留（`ps` 复核）。
- 报告落盘：`.work/gsd/phases/m2-5-color-grade/M2-5-ACCEPTANCE-OMP.md`，唯一写入。

OMP-VERDICT: PASS
