# M2-5-ACCEPTANCE-OMP-R2 — 「调色」双路并发终验报告（OMP 路）

> 验收员：OMP / 日期：2026-10-10 / HEAD：`f8e0671c` / 方法：正本亲读 + R1 抽查点独立机检重验（读码/git/ls/grep/计数），零测试复跑。

## 结论头

**PASS / 0 error + 1 minor**

- 三 ACCEPTANCE + R1 报告 + AGENTS.md M2-5 节 + M2-5-1-SUMMARY + M2-5-3-SUMMARY 勘误段全部亲读；R1 五抽查点逐项独立取证重验，无实质分歧。
- 唯一 minor = R1 已报注释异字，现状仍在（只读纪律未修），零语义影响。

## 抽查点 1：GradeCatalog 注册表 + defaultLook（独立重验 R1-§1 前半）

- `NodeOwnershipCatalog.swift:172-278`：现状 20 行 = M2-5 18 行（cat02WhiteBalance…filmGrain，:173-255）+ M3-3-02 filmPlacement 第 19 行（:263-266）+ M5-1-01 colormatch 第 20 行（:274-277）。**后演进，不记账**（R1 时态 19 行，其 HEAD `81b5df5`；colormatch 为 R1 后新增）。
- 前 18 行顺序/owner（.grade×14 + .drtPost×4）/shadows-highlights 共 shadhi 分立注记（:193-196）与 M2-5-1-ACCEPTANCE AC-1 ledger 一致；`item(opName:)` 查询面 :282-284 在位。
- `defaultLook` 三 entry :297-307 = exposure +1.5 / contrast +15 / saturation 1.3，与 R1 所引值逐值一致（行号后移 = 后演进插行）。

## 抽查点 2：V50Order 七新件位 + ACEScc envelope 缝（独立重验 R1-§1 后半）

- `V50Order.swift`：acesccIn 20.5（:61）< filmPlacement 20.8（:69，后演进）< exposure 21.0（:70）；colorWheels 41.0（:128，同位例外注记 :122-127 在位）；cat02 41.4（:132）/ contrast 41.6（:137）/ white 41.8（:142）/ black 41.95（:145，KD-3 挪位注记 :143-144）/ saturation 42.2 / tint 42.4 / hls 42.6（:152-154）；acesccOut 69.9（:229）。与 M2-5-1-SUMMARY 终位表逐位一致。
- envelope：`needsEnvelope` = GradeCatalog 查询面（`ACESccInModule.swift:126-128`），`wrap` 首尾包夹（:132-137），`install()` 注入 `LayerCompositeSeam.acesccEnvelope`（:141-143）。非白名单散抄判定成立。
- minor（R1 已报，现状仍在）：`ACESccInModule.swift:118` 注释「`boxes and铸 a fresh`」异字亲见，未修。零语义影响。

## 抽查点 3：LutLibraryStore 键/shared/切根 + Registry 接线（独立重验 R1-§2）

- 共享 holder：`LutLibraryStore.swift:105-106` NSLock + sharedInstance，锁内读 getter（:112-116），`replaceShared` 原子换（:121-125），`SharedForwardingResolver` 转发（:132-138）+ `sharedResolver`（:138）。checker m6 形亲证。
- 键升级：`InstalledLut.relativePath/subdirectory` additive optional（:74-77）；legacy 无字段行按 key 派生（:209-221）；`resolvedKey` 三段（精确→唯一尾段→歧义 nil，:367-375）；`lut(named:)` nil 缺席（:413-416）。根下文件退化面见头注 :22-27。
- 切根：`validateRoot` = isDirectory 守卫 + 写探针即建即删 + 无 bookmark 注记（:153-166）；键拼写 `"lut.library.root"` 字面全仓（IOP/App/Tests grep）唯一定义点 = :145 常量，init 消费 `Self.libraryRootKey`（:196）。
- 递归：`enumerator(at:)` + `skipsHiddenFiles`（:269-270）；`Registry.swift:421` lut3d 注册行走 `sharedResolver`（R1 引 :405-407，行号后移 = 后演进插行）。

## 抽查点 4：许可链（独立重验 R1-§3，全项亲测）

- `Resources/LUTs/` = 42 项（`ls|wc` 实测；40 `.cube` + LICENSE + NOTICE）。首尾名 Agfa_Vista_100 … Kodak_Vision_320T_5277 与 evidence 对照表形态一致。
- 40/40 全 `LUT_3D_SIZE 65`（grep 计数零脱漏）；抽 3 张 TITLE = 裸 stock 名（Portra_400/Fuji_C200/Kodak_5222）；`D:\Projects` 40 张内零命中；`alcedo` 全包唯一命中 = NOTICE 内「no bytes were copied from Alcedo Studio」声明句；Kodak_5222 首行 RGB 三列相等（灰度特征）。
- LICENSE 头 = `MIT License` + `(c) 2026 Jan Lohse`；NOTICE 载 v0.18.2 + SHA `42f4f3f…ce5f`；evidence 双文件在位（10KB/13KB，2026-10-01）。GitHub API 未重复打（R1 口径：包内字节 + 首验 API 记录已闭环，本批认同）。

## 抽查点 5：打包形态 + 测试登记 + E7 闭合（独立重验 R1-§4/§5 机检面）

- `Project.swift:179` `.folderReference(path: "Resources/LUTs")` 在位（另 :187/:192 为 FilmProfiles/AIModels 后演进行）；squash `747296f2 "M2-5: color grade…"` 主干可考。
- E7 闭合测试 `testAllCatalogOpsAreDefaultFaceRegistered` 在 `GradeCatalogTests.swift:130` 在位；该文件 15 法，`LutLibraryRecursionTests` 16 法，与 BUNDLE-MAP（APP 15 :243 / IOPP 16 :106）精确一致。
- 计数断言现状 20/16（:39/:55），方法名仍 `…Eighteen…`/`…Fourteen…`——R1 时态 19/15，名实差再扩大一行系 M5-1 后演进。**后演进，不记账**（M2-5 时态名实相符，首验 AC-1 成立）。
- 本批零测试复跑（引用 R1 定向复跑 15/0/0 + 16/1/0 与三首验 `--all` 终值；代码面自 R1 起 M2-5 文件零改动证据 = 行注释来源注记完整 + 登记计数一致）。

## 分歧项

**无实质分歧**。三 plan PASS、计数链、许可 MIT 结论、键语义申报，独立取证全部成立。仅两处时态注记（非分歧）：① R1「现状 19 行」在其 HEAD 下成立，现 20 行系 M5-1 后演进；② R1 引 Registry :405-407/defaultLook :286-296 等行号后移，均为后演进插行，语义逐项复核无变。

## FAIL 明细与可修性

不适用（PASS）。唯一 minor（ACESccInModule 注释异字）= 一字小修，建议随任一触碰该文件的后续提交顺手修复。

OMP-VERDICT: PASS
