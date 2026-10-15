---
phase: V2-Maintenance
slug: v2-maintenance
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
---

# Phase V2/Maintenance — Validation（缺陷修复波 1 + 清算波 2：双 plan 双路独立验收全 PASS 的闭环签核）

> 体例对齐 `phases/m6-4-gallery-stacks/M6-4-VALIDATION.md`（正本链上溯
> `phases/m2-11-performance/M2-11-VALIDATION.md`）。**双重验收
> （dual_acceptance）两波各两路全部落终态后成文**：波 1（`V2M-01`，缺陷
> 修复批 D-1..D-5）双路 zcode 独立验收 PASS / 0 error + 0 minor——三路
> （执行方 + 两验收路）全套 `--all` **3851/35/0 同值**（2047s/2045s/2053s），
> 正本 = `V2M-01-ACCEPTANCE.md` / `V2M-01-ACCEPTANCE-2ND.md`；波 2
> （`V2M-02`，清算批 V17 + PATCH-LIVEPLANE + RELEASE-DIRECT-INJECT +
> EXPORT-PRESET-01 + T2 走查批）双路 zcode 独立验收 PASS / 0 error +
> 0 minor——终态 **3857/35/0**（执行方 2047s + 第二路全套亲跑 2117s
> 逐位闭合；第一路全套轮 App bundle 一次窗外测试环境型 crash → 单独重跑
> 824/4/0 绿 + 合并对账 3857 闭合，归因环境型 flake，正本 =
> `V2M-02-ACCEPTANCE.md` / `V2M-02-ACCEPTANCE-2ND.md`）。**两波两路
> 零实质分歧**（波 2 第一路的条件性全套轮注记与 D-4「返工不触发」追认、
> D-6 error 级定级表态均被第二路独立复核一致）。**翻账只认证据**：
> SC 生效值对账正本 = `V2M-CONTEXT.md`（OQ-VM-1..5 全 A）+ 两 plan
> PLAN/SUMMARY/DECISIONS + 四份 ACCEPTANCE 六份亲跑/亲读记录；charter
> 验收形态（两 plan 各自 PLAN §AC）逐条兑现见下两表。**SC 数字对账终态 =
> 全套 `--all` `TOTAL|3857/35/0|`，对账链 3848（M6-5 T9 基线，M6-6 批
> ΔN=0 同值维持）+ ΔN₁ 3（波 1）+ ΔN₂ 6（波 2）= 3857 精确**；skip 35
> 构成 = 基线恒有 24 + 真 RAW 供件域漂移 11（先于本 phase 5.5h 发生的
> 环境漂移——TestRAW 目录 mtime 10-15 15:44 早于 planner docs 20:40，
> 两路独立逐族差分亲证；非本批静默跳过，本批唯一供件级新法
> `testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace` 真跑未 skip）。
> 执行链：波 1 `54124c7e..bb16f8c4`（6 commits）+ 波 2
> `2ba1d1fe..08f9ebc4`（5 commits）。**批内新缺陷三笔（D-6/D-7/D-8）
> 登记不修，转下一修复批（D-6 首项）；波 1 屏面证据四项义务延续至 D-6
> 修复后走查批**——见 §挂账总汇编。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest。**波 1 +3 法**（App +2：`testSnapshotRefreshFollowsTheCommittedRecord` / `testLiveWindowOverridesTheSnapshotUntilCommit`〔D-1 快照缝两钉〕；IOP +1：`testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`〔D-2 供件级回归钉——GREENCAST-7RM5.ARW untracked 域，缺席 XCTSkip，本 phase 全套轮真实 executed〕+ 既有 `testResolveDecoderVersionMatrix` 矩阵更新 + `testRAW9OptIn` 同缝重钉）；**波 2 +6 法**（App：AIMaskPatchFlowTests +2〔PATCH-LIVEPLANE 切层/切图两钉〕+ `ExportPresetTests` 新文件 +4〔round-trip 四法〕） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL/crash 签名/no-total-line 机检全挂靠——L055 双保险本 phase 四路亲证有效：第一路 App crash 轮被正确置零计数**非假绿**） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3857 tests / 35 skip / 0 fail**（执行方 2047s + 第二路 2117s 两轮独立亲跑同值，exit 0 零 MEMFAIL，七 bundle 全 8G 门内）；逐 bundle（第二路终轮）：IOP **687/5/0**〔7278MB〕/ IOPParity **460/3/0**〔8108MB 贴线带内 7242..8111〕/ Layers **494/5/0** / Library **729/4/0** / Sessions **284/9/0** / Export **379/5/0** / App **824/4/0**——段和 687+460+494+729+284+379+824 = 3857 机械闭合 |
| **基线演变** | 3848（M6-5 T9 基线；M6-6 批 ΔN=0 同值）→ 波 1 +3（ΔN₁ = T1 +2 / T2 +1）= **3851**〔三路同值〕→ 波 2 +6（ΔN₂ = T3 +2 / T5 +4，App 818→824）= **3857 终态**；对账链 3848+3+6 = 3857 精确 |
| **skip 35 构成声明** | 基线恒有 24（SkinRegion 1 / ColorChecker+ManualProbe 3 / AIMask+Bake+GradePerf 4 / Library Benchmark+ThumbObs+GPS 4 / CatalogBench+Perf07 4 / PerfProbe 4 / Depth 4）+ 真 RAW 供件域漂移 11（IOP RAWDecoderTests×4〔testDecodeARW / testDecodeDNG / testDecodeIsCancellable / testRAW9OptIn 本机臂〕+ Sessions SessionThumbnailProviderTests×5 + Layers `testRealRAWRoundTrip`×1 + Export `testRealRAWWalk`×1）——`Fixtures.arw`/`Fixtures.dng` + Plan-05 samples 域缺席、`LIGHTAMER_RAW_SAMPLES_DIR` 未指；**漂移时点先于本批 5.5h**（TestRAW mtime 10-15 15:44:46 < planner docs 20:40-20:54 < T1 执行 21:20），两路独立逐族差分亲证 |
| **在案发现（本 phase 事件）** | 两波四路 **零 error 级产物缺陷、零 open minor**；新缺陷三笔 = 走查批登记不修（D-6 error 级候选 / D-7 导入停滞 / D-8 legacy 会话不可达 → §挂账①）；环境型 flake 两笔（波 1 GrainTests 定向轮单次 + 波 2 ProcessVersionCarrierTests 全套轮窗内一次）→ flake 台账延续（§挂账⑤）；批内抓修 = V17 门 `%@` 正则 bug（`2ba1d1fe` 内修——首跑分诊两 String-arg 键幻红即修）+ 测试时序裁量两笔（mid-flight 6000² 放宽 bake 窗 = 测试专用构造零产线缝 / GrainTests 净轮取值） |
| **GUI 证据** | **Blocked-Channel 如实登记不硬造判定**（CONTEXT OQ-VM-5 先例条款）：波 1 屏面证据四项 Blocked-Env（通道堵点诊断证据在 `gui-acceptance/v2m/MANIFEST.md`）；波 2 T2 走查批三条独立通道受阻（D-6/D-7/D-8）收兵，可达行集缩水为零逐行终态在 MANIFEST；**DONE 面** = D-2 修前绿染复现 + 修后视口复验 + Preview.app 交叉证人 + T1 面板挂载部分面（波 1 walk-0/9/10/15 四截图）——V2M-D2-02 视口复验 PASS 亲证（两路识图独立复核）；M6 收口走查行 03/05/08 色彩目测前提恢复声明（D-2 解锁）+ 06/07 数值面仍待走查 |
| **zh 对账** | 波 1 xcstrings **零 diff**（D-5 主形态 = 调用点 `Int((holeFraction * 100).rounded())` 对齐在册 `%lld` 变体，翻案口未行使）；波 2 = T1 清偿键 17 行 + T5 预设键族 119 行 = **136+/0- 两批尾块纯插入**（历史键字节与顺序零触碰）；`zh-audit --check`（**V17 新门**）+ `--self-test` 八例 PASS 四路独立亲跑；UserDefaults **全 phase 唯一新键 = `export.presets`**（AGENTS 已登记，既有 `export.*` 六键零触） |

---

## 波 1（V2M-01）SC/AC 生效值对照（OQ-VM-1/2 裁决落点终态）

| # | 生效值（CONTEXT 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **D-1 追色按钮零响应 = binding get 热观察读取去热化**（RESEARCH 根因面 + plan 修法）：params 快照化 + updateInstance 兑现 + view 级 onChange seam + Film/Drt 孪生三分裁定 | T1 `54124c7e` | **Delivered**：`snapshotParams`/`snapshotRecord` 存储属性 + `updateInstance` 钩子兑现（:54 doc comment 缺席许诺补足）+ 四刷新点（init / `.onChange(of: instance)` 非 nil 作用域 / solve 回填 `refreshSnapshotFromChain` / `commitStrengthDrag` 尾 live 值臂）；grep 机检 = params/currentRecord getter 体 `pipeCoordinator` 零命中；**Film/Drt 三分「健康」两路独立读码复核成立**（`effectiveFilm/DrtRecord` = 已物化数组尾扫零 JSONDecoder，与 ColorMatch「每读线性扫 + 每读解码」不同构——「无实测证据不预防性重写」裁定合规，两文件零 diff）；五路径覆盖（切换/commit/MCP/undo-rebuild/init）onChange seam 全盖，两路独立走链均未发现第六路径；C-2 竞争窗 live 值臂论证自洽（第二路陈旧窗分析：拖动 commit 同步臂 0 窗 / 外部写 ≤1 帧自愈无累积漂移）；+2 法判别力亲证（缺 `refreshSnapshot` 或缺 live 值臂恰红） |
| 2 | **D-2 视口绿染 = 三段式验收（bisect 裁定 → 修法落地 → 回归钉），修法形态留执行批按实测裁**（OQ-VM-2=A） | T2 `5567b56c` | **Delivered（automatic 收紧裁定）**：bisect 七步坐实**毒化腿 = CI 色管理转换 × v9 CoreML 输出**（unmanaged v9≈v8 近同平衡证伪「解码本身毒」；working-space 腿 v9 linMeans G/R≈3.87 毒 vs v8 1.065 净；对照文件中性；Preview.app 证人）——transcript + 探针输出 = `evidence/V2M-01/d2-bisect/`（local-only）；**裁定 = `.automatic` 恒 v8**（纯函数缝零 `.metal` 零红线零 UI 改；白名单不可建立〔beta 名单逐季扩张〕+ 健全性门无法区分夜景绿树——三选取舍为机制性论证，两路独立复核成立）；正例对照 spread 修前 0.742（应红）/ 修后 0.062（绿）；三面回归钉（供件级 spread<0.5 + resolve 矩阵 automatic 三臂全 v8 零供件依赖 + `testRAW9OptIn` 重钉）；**关键实验第一路 swiftc 直编探针复跑**（automatic→v8 净 / forceV9→v9 毒逐位重演 / forceV8→净）；**遗留面亲证登记**：forceV9 显式档仍毒（§挂账③） |
| 3 | **D-3 filmstrip 换图钉序 = 单一换图通道收敛 + 陈旧任务竞态封闭** | T3 `83f48bbb` | **Delivered**：grid onChange 与 filmstrip onOpen 两腿并入 `switchCurrent(to:)`（phase guard + `openCurrent` + 单 phase 写幂等；旧 onOpen 腿缺 openCurrent 收敛的双真相序消除）；`loadCurrentImage` 唯一 pre-write await 后补 `Task.isCancelled` dead-drop——检查点到状态写同步段无 suspension point，`.task(id:)` 超替任务死于状态写前 = **竞态结构性封闭**（第二路逐 await 清点独立复核：无第二 pre-write await 漏防 + store nil 作用域恰覆盖 + 取消传入时 marker 不清良性）；「未换」观感假象 = A/B 字节相同副本（cmp 亲证）与真 stuck 类分层清晰；ΔN=0 记账合规（视图级 seam 不可纯函数化，DECISIONS 申报） |
| 4 | **D-4 合并对话框「0 张」= `.sheet(item:)` payload（arm 点构造计数随 item 进闭包）+ 返工预案触发条件明确** | T4 `e74be37b` | **Delivered**：三计数对话框（focus_stack/stack_denoise/hdr_merge）arm 点构造 `MergeDialogCount(count:)` 随 item 进入内容闭包——计数绑定呈现触发本体，与呈现快照两机制解耦；动作面零改；`pendingTargets.count` 文件内零命中 + 三标题行读 `dialog.count`；**「快照上移」返工预案触发条件三要素齐备**（复验仍见 0 → 快照上移 → 一轮损失）；**波 2 双路追认「返工不触发」裁定成立**——触发前提 = 对话框实际呈现，D-6/D-7/D-8 阻断下从未呈现，「通道不可达 ≠ 复验见 0」；代码面证据链波 2 本路全套轮 Sessions 284/9/0 再证无反证 |
| 5 | **D-5 toast 裸键名 = 调用点 Int 化对齐在册 `%lld` 变体（xcstrings 零改动）** | T5 `8133726e` | **Delivered**：`Int((holeFraction * 100).rounded())` 对齐 `%lld`（半分界 away-from-zero 已记 DECISIONS）；RESEARCH「补 %lf 变体」翻案不行使（`%lf` 会渲染「12.340000%」反劣化）；xcstrings 零 diff；**波 2 V17 门活体绿例亲证**（函数参数 + Int 包装推导 → `%lld` 命中，derivable 8 键中不 EXEMPT 不 mismatch——E-2 供给面修订失守哨兵未触发） |
| — | **AC 零回归门（波 1）** | T6 + 四路机检 | **Delivered**：`git diff 7b252db1..bb16f8c4` 全批 9 文件 337+/75-（fix 链）；`LightamerIOP/` 零 diff；全部 `*.metal` 零 diff（D-2 修订口未行使）；`Project.swift` 零 diff（零新 SPM/零新测试文件）；`*.xcstrings` 零 diff；封存面（Pipe/History、Sidecar、DrtRecord、GradeCatalog、Registry、V50Order、六格式矩阵）零 diff；`\.runModal(` 零命中；LocalizationValue 插值禁形零命中；UserDefaults 零新键；`zh-audit --check` PASS |

## 波 2（V2M-02）SC/AC 生效值对照（OQ-VM-3/4/5 裁决落点终态）

| # | 生效值（CONTEXT 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | **V17 zh-audit 门扩展（M6-5 挂账③兑现）= specifier 深检 + Text 族 + 跨行族合门 + 八例 golden + 活体清偿** | T1 `2ba1d1fe` | **Delivered（含批内抓修）**：断言 6 = 插值键实参静态类型**逐参有序比对**目录变体 spec 序（全 Int 族→`%lld` / Float|Double→`%lf` / String→`%@`；`%@` 显式入正则字符类——首跑 `%[a-zA-Z]+` 不覆盖 `@` 两例幻红批内即修，教训入册）；Text 族（单行 + 行尾续行形）合门；EXEMPT 供给面收窄禁误报（成员链/闭包参数/未注解 let 等）；**golden 八例 `--self-test` PASS**；活体清偿 `catalog_session_remove_confirm_body %@` 尾块纯插入 17 行（SidebarView:262 裸键 face 根治，调用点零改）；第一路独立 fixture 端到端亲测（位置洞 `p1_position`〔String,Int〕vs `%lld %lld` 恰红 = 集合交集形会放行的洞被关闭）；活树 `--check` PASS（1688 source / 1936 catalog / 38 interp 全 variant-PRESENT + spec-matched）；C-3 预言命中（McpLauncher 三键 EXEMPT 非绿、断言 5 层 PRESENT 过） |
| 2 | **T2 Manual-Only GUI 走查批 = 「不硬造判定」纪律 + 通道受阻如实登记**（OQ-VM-5=A） | T2 无 commit（local-only） | **Delivered（通道受阻收兵裁定，两路追认）**：三条独立通道阻断——**D-6（error 级候选）**重开项目态编辑器不可用：视口 legacy 空态卡/黑 + filmstrip 24 步循环零响应 + 主线程 SwiftUI AttributeGraph spin（CPU 99.9%，sample 1094/1094 全框架帧零 app 帧；**第二路严格独立复现**：6 图项目 + osascript 菜单通道配方亲跑 + sample 1233/1233 亲采 + AX 恶化佐证——与波 1 D-1 修法隔离性两路亲证〔D-1 触 ColorMatch params 面，D-6 栈全在 ShellView 布局面〕，对照组波 1 同会话新建路径健康）；D-7 导入停滞（波 1 批外疑点同面复现，M2-9 F-1 家族疑似）；D-8 legacy 会话建立不可达；四 V2M 专属行（V2M-T1-02/D3-01/D4-01/D5-01）Blocked-Channel 保持 + **D-4「快照上移」返工预案不触发**（触发前提 = 对话框呈现，通道不可达 ≠ 复验见 0）；harness 通道改良正向偏差（menu AX 下钻修复波 1 堵点，项目重开/save sheet/Import Folder 全机检可达）；m6-closeout 余行逐行终态在 MANIFEST；证据 = `.work/gui-acceptance/v2m/`（t2-spin.sample.txt + diag-*.png + d3_cycle.py） |
| 3 | **PATCH-LIVEPLANE（M6-4 挂账⑤移交）= 余量盘点 → 余量非零修复臂（E5 两残差实修）** | T3 `4914619c` | **Delivered**：E5 残差①「末次 pass 后无 pending debounce 时平面驻留」+ 残差②「confirm 在飞切图 stamp 污染」对照 `b49215bb` 主修面盘点 = 确实 open（销账臂不成立有据）；修复三件——①eager 释放双点（`LayerEditingState.select` 异值 + `EditorAreaView.onChange(of: loadedImageURL)`）②`armedImageURL` 函数头捕获 + segment 腿**装载门**（gate→stamp 同步段无 suspension point，D-3 检查点模式同构）③stamp 恒取 armed；污染路径封闭性两路独立走查成立（**第二路 armed 双写窗口亲核 = 窗口不存在**）；两新法判别力亲证（无 eager 释放恰红 / 无装载门恰红；6000² 放宽 bake 窗 = 测试专用构造零产线注入缝，潜在假红方向只产 flake 不造假绿）；N6 孤儿 bake 文件缝观察项登记（§挂账⑥） |
| 4 | **RELEASE-DIRECT-INJECT（M6-5 转 V2 件）= 余量盘点 → 主债形态已消防御脚本入库** | T4 `4ca893cb` | **Delivered（PROBE PASS 亲证）**：当前依赖图新 Release 构建无 PackageFrameworks 目录——WebP 静态内联进 LightamerCore（nm 零 webp 未定义符号），直启探针零修复 PASS（rc=0 + 主窗 up；transcript = `evidence/v2m-02-t4/`）；`Scripts/make-release-direct-launchable.sh`（110 行零产线 diff）= SPM/Tuist 链接代际回摆自愈通道（embed PackageProduct frameworks + ad-hoc 内层先签 + 直启探针 + 探针毕自起实例静默 kill）；make-dmg embed 缺口翻账建议在案（§AGENTS 登记） |
| 5 | **EXPORT-PRESET-01（Alcedo 对标候选）= 命名导出预设层入波尾**（OQ-VM-4=A） | T5 `de786663` | **Delivered**：`ExportPresetStore` 独立文件（NamingTemplateStore 同款纪律——注入式 defaults / 全量替换写回 / 三内置不入库〔JPEG 90 / TIFF 16-bit / WebP 85〕/ 坏 JSON 降空库；ExportState **零 diff**）；**捕获面 = REQUIREMENTS :401 清单精确**，`collisionPolicy` 与 `gainMapHDR` **结构性不入捕获面**（`ExportPresetPanelFace` 值面不带 = M-5/M3-1-03 KD-1 编译期钉死 + 运行期 applyFace 无写点 + 测试②先设 `.fail`+gainMap=true 后断言原值——pin 三重亲证）；套用投影 = 纯函数 `ExportPresetProjector.project`（悬挂模板 → `builtIns[0].pattern` 引用回落；variant validate 失败 → 整面回 defaultFace 禁半落地）；round-trip 四法；**UserDefaults 唯一新键 `export.presets`**（唯一写点 :306；既有 `export.*` 六键零触）+ `export_preset_*` 七键尾块纯插入；Project.swift 恰一行 + BUNDLE-MAP 同批登记 + tuist generate 恒末位（L041） |
| — | **D-5 条件任务（若波 1 未清则并此）** | T6 | **零动作**（波 1 T5 已清 + 波 2 T1 V17 首跑绿例亲证——D-V2M2-6）；Export 定向轮 379/5/0 = 波 1 终值同值（封存面零触佐证） |
| — | **AC 零回归门（波 2，两波合并窗 `7b252db1..08f9ebc4`）** | T6 + 四路机检 | **Delivered**：全部 `*.metal` 零 diff；`LightamerIOP/` 全域零 diff；`LightamerSidecar.swift` 零 diff；封存面（DrtRecord/GradeCatalog/Registry/HistoryStack/V50Order/ExportFormatSpec/ImageIOEncoders/WebPEncoder/ExportQueueContract）全零 diff；`Project.swift` 全窗恰一行（ExportPresetTests 登记；dependencies 块零 diff 零新 SPM）；`*.xcstrings` 全窗 136+/0- 纯插入；`\.runModal(` 零命中；LocalizationValue 插值禁形代码行零命中（:2069 doc comment 豁免锚）；UserDefaults 全窗唯一新键 `export.presets` |

---

## 双重验收记录（dual_acceptance 链，两波各两路）

| 路 | 结论 | 证据要点 | 分歧与处置 |
|---|---|---|---|
| **波 1 第一路 zcode 独立验收**（2026-10-16，零共享上下文） | **PASS / 0 error + 0 minor**（+1 条件通过注记 + 2 验收注记 N-A/N-B） | 全套 `--all` 自建亲跑 **3851/35/0**（2045s）exit 0 + D-1 五路径独立走链 + **D-2 关键实验 swiftc 直编探针复跑**（automatic/forceV9/forceV8 三臂逐位）+ D-3/D-4/D-5 逐项亲读 + skip +11 独立核实（先于本批 5.5h 非静默跳过）+ 红线族亲跑 + GUI 截图识图亲验（修前绿染 vs 修后自然色） | 条件通过注记 = GUI 屏面四项挂 V2M-02 T2 硬义务；N-A 供件钉 doc comment 措辞精度 / N-B plan files_modified 漏列 RAWDecoderTests——均非缺陷 |
| **波 1 第二路 zcode 独立眼**（零共享第一路上下文） | **PASS / 0 error + 0 minor**（+同款条件注记 + 4 条自产执行注记 E2-1..E2-4） | 全套自跑 **3851/35/0**（2053s）三路同值 + 五面独立审计（快照陈旧窗分析〔拖动 commit 0 窗/外部写 ≤1 帧自愈〕/ 收紧前向安全〔switch 自家枚举非 CIRAW 穷举——RAW 10 零编译破缺〕+ 两回归钉正交性 / 竞态逐 await 清点 / 义务链完备性 / 四偏差+两疑点复核）+ 红线族独立重跑 | 与第一路零实质分歧；E2-2 = 收紧质量代价显式化建议（X-Trans v9 质量面随退场）→ **本闭环批 AGENTS 落账**（§挂账③）；E2-1 = V2M-02 T2 派发须显式列四行 id（已兑现） |
| **波 2 第一路 zcode 独立验收**（2026-10-16） | **PASS / 0 error + 0 minor**（+1 条件性全套轮注记 + 4 验收注记 N1..N4） | 全套亲跑 = 六 bundle 逐位与申报一致 + App 单独轮 **824/4/0** 绿（全套轮 App 宿主在窗外既有 `ProcessVersionCarrierTests.testUndoToTopAndVersionSwapLeaveTheValueUntouched`〔M5 时代，远早于本批〕异常退出 exit=133，L055 正确置零非假绿；本批 +6 新法 crash 轮内已全部 executed+passed = 与 Δfiles 无关）→ **合并对账 687+460+494+729+284+379+824 = 3857 精确**；V17 逐参有序比对独立 fixture 亲测（位置洞恰红）+ T3 污染路径走查 + T5 pin 三重亲证 + T4 probe transcript 硬证据；**D-6 定级独立表态成立**（用户面/机检证据/隔离性/对照组四要素）+ D-4 裁决追认 | 条件性注记 = App crash 环境型归因（第二路全套轮未复现 → 复现率 1/3 加强归因）；N1 T3 文件落位偏差未申报 / N2 EXEMPT 30→31 口径 / N3 幻红期无 transcript / N4 位置洞活体覆盖落空（EXEMPT 设计行为）——均注记级 |
| **波 2 第二路 zcode 独立眼**（零共享上下文） | **PASS / 0 error + 0 minor**（+2 自产注记 N5/N6） | 全套新鲜构建亲跑 **3857/35/0**（2117s）exit 0 逐位闭合（App bundle 本轮全绿——第一路 crash 未复现，三轮 1 次复现环境型归因加强）；V17 四边界独立 fixture（`%@` 混排多参绿 / 位置参数变体键名 MISMATCH 红 = **假红安全方向**）；T3 armed 双写窗口不存在亲证；T5 持久化/apply/round-trip 全链；**D-6 严格独立复现**（6 图项目空态卡不一致态 + AG spin 栈 1233/1233 亲采 + 复现配方可执行性亲证）；偏差四项 + 第一路 4 注记全部追认 | **零实质分歧**（全套轮数字与第一路合并亲证互证；crash 判定一致）；N5 = `String(localized:defaultValue:)` + 位置占位形态断言面外盲区（现状零活跃缺陷面，调用点已手动 stringify）→ §挂账⑥；N6 = 孤儿 bake 文件缝观察项 → §挂账⑥ |

四路终态：**零 error、零 open minor**；波 1 三路全套同值 3851/35/0 + 波 2
终值 3857/35/0 逐位闭合（第一路窗内 crash 单独重跑绿 + 合并对账精确）——
**双波双路零实质分歧，dual_acceptance 意图满足**。

## Per-Plan Map

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| V2M-01（波 1 缺陷修复批） | T1 D-1 快照去热读（params/record 快照 + updateInstance + onChange seam + Film/Drt 三分健康）→ T2 D-2 bisect + automatic 收紧 + 三面回归钉 → T3 D-3 换图单通道 + 竞态封闭 → T4 D-4 sheet(item:) payload → T5 D-5 toast Int 化 → T6 收口 | worker 六提交 `54124c7e..bb16f8c4`；未 push | 双路 PASS / 0 error + 0 minor；三路全套 3851/35/0 同值 |
| V2M-02（波 2 清算批） | T1 V17 门扩展 + 活体清偿（含 `%@` 正则批内抓修）→ T2 Manual-Only 走查批（通道受阻收兵 + D-6/D-7/D-8 登记）→ T3 PATCH-LIVEPLANE 修复臂 → T4 RELEASE-DIRECT-INJECT 防御脚本 → T5 EXPORT-PRESET-01 预设层 → T6 条件任务零动作 + 收口 | worker 五提交 `2ba1d1fe..08f9ebc4`；未 push | 双路 PASS / 0 error + 0 minor；终值 3857/35/0（第一路窗内 crash 合并对账闭合） |

零红线域终态（两波四路亲跑，`7b252db1..08f9ebc4` 全窗）：`.metal` 全域 =
**0 diff**；`LightamerIOP/` = **0 diff**；`.lra` sidecar schema
（`LightamerSidecar.swift`）= **0 diff**；封存面九件 = 0 diff；
`Project.swift` = 恰一行测试登记（dependencies 块零 diff，**零新 SPM**）；
UserDefaults = **恰一键 `export.presets`**；runModal = 0；LocalizationValue
插值禁形 = 0；xcstrings = 136+/0- 纯插入（17 + 119）；V17 门红线电池引用形
= `--check` PASS（ABSENT/MISMATCH 零命中）+ `--self-test` PASS。
V2/Maintenance 修法形态与门约定见 AGENTS「V2-Maintenance 架构增量」节。

---

## 挂账总汇编（V2/Maintenance 单一移交清单，六项）

1. **新缺陷三笔 D-6 / D-7 / D-8 → 下一修复批（D-6 首项）**：**D-6（error
   级候选）** = 重开项目态编辑器完全不可用 + 主线程 SwiftUI AttributeGraph
   spin（CPU 99.9%，sample 全框架帧零 app 帧，SystemSplitView/
   SplitViewCoordinator formCurrentItems AG update 循环——m6-closeout D-1
   layout churn 同族；修复批可从「重开项目态的 view graph 循环更新源」切入，
   与波 1 批外疑点①项目面 colormatch `hasImage=nil` 疑同域）；**D-7** =
   导入停滞（Media 拷贝完成后 >10min 未发布完成态，主线程活跃非挂死——
   M2-9 F-1 家族疑似，两波各复现一次）；**D-8** = legacy 会话建立通道不可达
   （`LIGHTAMER_LEGACY_LIBRARY=1` 面文件>打开/Import Folder 腿无响应；
   V2 #4 SESSION-LEGACY-READONLY 若立项应先修通道）。证据族 =
   `gui-acceptance/v2m/`（t2-spin.sample.txt + diag-*.png + d3_cycle.py +
   import-stall-sample.txt，local-only）；两路独立复现配方亲证可执行。
2. **波 1 屏面证据四项 + D-4 复验 → D-6 修复后走查批硬义务**：V2M-T1-02
   （D-1 三零消除点击）/ V2M-D3-01（D-3 加固循环）/ V2M-D4-01（D-4 标题
   计数——**若复验仍见 0 按「快照上移」预案返工，一轮损失不产假交付**）/
   V2M-D5-01（D-5 toast zh 文案）；连带 m6-closeout MANIFEST 行 03/05/08
   （D-1 代码面已清待屏面）+ 06/07 复走 + m6-closeout 余 Blocked-Channel
   行随通道恢复复走；派发令引用正本 = `V2M-01-ACCEPTANCE-2ND.md` §五
   E2-1 + `V2M-02-ACCEPTANCE.md` §六。
3. **forceV9 显式档仍毒 + X-Trans v9 质量面退场 → AGENTS 登记（本批已落）**：
   用户显式行为（面板有 readout/downgrade 提示）不改；**X-Trans/Quad-Bayer
   机身的 v9 demosaic+denoise 质量面随 automatic 收紧一并退场**（E2-2——
   STACK.md 载 X-Trans 恰是 RAW 9 ML 引擎收益最大处，富士机身当前实际无
   可用 v9 路径）；重入口条件 = 探针 WS 腿对 v9 能力机身转中性后恢复
   opt-in（`evidence/V2M-01/d2-bisect/TRANSCRIPT.md` 重启条件节）；既往
   automatic 文档重载后 decodeParamsHash 一次性漂移（重渲非数据损失）。
4. **RAW 供件缺失 11 skip → 供件备料后收敛（用户侧供件）**：`Fixtures.arw`
   / `Fixtures.dng` + Plan-05 samples 域缺席 + `LIGHTAMER_RAW_SAMPLES_DIR`
   未指；备料后 11 法自动归队（3857 基线 skip 面收敛至 24；本批唯一供件级
   新法已用 `input/RAW/GREENCAST-7RM5.ARW` untracked 域部分回填真 RAW 测试面）。
5. **环境型 flake 两笔 → flake 台账延续**：波 1 GrainTests 定向轮单次
   （同码 T2 轮全绿 + 单类复测 8/0/0 + diff 窗不含 grain 面 → GPU 状态序
   漂移，M2-7-3 先例族）；波 2 ProcessVersionCarrierTests 全套轮 App 宿主
   一次窗外 crash（exit=133，单独重跑绿，三轮 1 次复现，AGX Texture
   assertion GPU 驱动层环境签名；L055 置零机制正确非假绿）——均按
   「留证 + 净轮取值 + 不升级归因」先例处置，M2-11-01 flake 台账谱系延续。
6. **V17 位置参数变体键名假红（安全方向）+ N5/N6 观察项 → 登记备查**：
   V17 门把 `%1$lld` 位置参数变体键名解析为空 spec → MISMATCH 假红
   （**失败方向 = 假红非假绿**——门拦下要求人工复核不静默放行；活树零此类
   键名，在册 5 处 `%1$@` 全在 value 文本非变体键名）；**N5** =
   `String(localized: "K", defaultValue: "…\(x)…")` + catalog 位置占位
   形态为断言面外盲区（活树 5 键在册、调用点已手动 stringify 规避 crash，
   现状零活跃缺陷面——后续批可选扩展）；**N6** = T3 在飞切图竞态下孤儿
   bake 文件缝（非正确性问题，严格优于修复前形态；修复批如触
   masksDirectory 可顺带收口）。

另有**登记级观察**不占挂账（四路在案，零动作）：N-A 供件钉 doc comment 措辞
精度 / N-B plan files_modified 漏列（两波同族——plan 侧预测不全，语义重钉
与落位文件宜预列）/ E2-3 testRAW9OptIn 本机 skip 态由矩阵+供件钉同事实覆盖
（样张回填后自动归队）/ E2-4 solve 回填刷新无直接单测（seam 一帧兜底无用户
可见面）/ N1 T3 文件落位偏差未申报 / N2 EXEMPT 30→31 清偿后口径 / N3 幻红
期无 transcript（过程证据缺口）/ N4 逐参有序比对活体 derivable 覆盖 = 0
（EXEMPT 禁误报设计行为，位置洞防护由 golden g5 + 独立 fixture 承担）/
make-dmg.sh embed 缺口（分发批并入 make-release-direct-launchable 或前置
调用——AGENTS 登记）。

**批内已清偿**不占挂账：D-1..D-5 五缺陷代码面（波 1 五 commit）+ N-1
McpLauncher 三键销账维持（M6-6 rider `d63cf79c`，CONTEXT §二勘误正本）+
E5 PATCH-LIVEPLANE 两残差（`4914619c`）+ RELEASE-DIRECT-INJECT 债形态
（已消 + 防御脚本入库）+ V17 门活体清偿键 + EXPORT-PRESET-01 全件。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。五项 OQ 生效值（OQ-VM-1..5 全 A）+
  两 plan 全部 AC 每条均有 ≥1 机器锚（波 1：+3 法〔快照缝两钉 + 供件级
  spread 钉〕+ resolve 矩阵更新 + `testRAW9OptIn` 重钉 + grep 结构机检 +
  swiftc 直编探针三臂复跑；波 2：+6 法〔PATCH-LIVEPLANE 两钉 + 预设
  round-trip 四法〕+ V17 `--self-test` 八例 golden + 双路独立 fixture
  端到端 + PROBE PASS transcript + 判别力亲证〔缺件恰红〕）+ ≥1 实证背书
  （波 1 三路全套同值 3851/35/0 + 对账链 3848+3 = 3851 精确 + skip 逐族
  差分 + bisect transcript 数字逐位亲核；波 2 两路终值 3857/35/0 + 段和
  机械闭合 + D-6 双路独立复现〔sample 1094/1094 与 1233/1233 亲采〕+
  D-4 追认 + 第一路 crash 三轮复现率 1/3 环境归因）。
- 采样密度：两波全 AC 逐条机检（+9 新法 + 既有面零回归双保险：六 bundle
  逐值零漂移 + 冻结/封存面零 diff 机检族）+ **每波双路零共享上下文独立
  验收**（各自自建 build + 各自全套 `--all` 亲跑，第二路证据亲跑/亲读重取
  不复述第一路）+ 修法深审均含独立复算/独立 fixture/独立探针（D-1 五路径
  独立走链 / D-2 三臂探针复跑 / V17 位置洞独立 fixture / T3 双写窗口
  亲核 = 窗口不存在）；「无证据 ✅」零项。
- 数字对账：波 1 三路互证（3851/35/0 逐值一致 + ΔN₁=+3 分解亲证 + 段和
  闭合）+ 波 2 双路互证（3857/35/0 = 3851+6 精确 + 第一路窗内 crash 合并
  对账链亲证 + 段和 687+460+494+729+284+379+824 机械闭合）；skip 35 =
  24+11 两波两路逐族差分一致。

## 特殊事项入册（phase 级事件台账）

1. **波 2 第一路全套轮 App 一次窗外 crash（环境型，非产物缺陷）**：宿主在
   窗外既有 `ProcessVersionCarrierTests`（M5 时代 commit `a33a6afd`，远早
   于本批）异常退出 exit=133，L055 机制正确置零计数非假绿；单独重跑
   824/4/0 绿 + 本批 +6 新法 crash 轮内已全部 executed + 第二路全套轮未
   复现（复现率 1/3）+ 日志前段 AGX GPU 驱动层环境签名 → M2-7-3 先例族
   （GPU 状态序漂移环境型 flake）同款归因；终值以合并对账 + 净轮为准。
2. **T2 通道受阻收兵（本 phase 最重裁定，两路追认）**：走查批开工撞三条
   独立通道阻断（D-6 编辑器 spin / D-7 导入停滞 / D-8 legacy 会话腿），
   按「不硬造判定」纪律收兵（CONTEXT OQ-VM-5 先例条款）——可达行集缩水
   为零如实逐行登记；**harness 与 app 内容面分账诚实**（menu AX 通道改良
   为正向偏差：波 1「项目重开 flaky」形态不复现，失败面全在 app 内容面）；
   D-4「快照上移」返工预案**不触发**（通道不可达 ≠ 复验见 0，触发前提
   未被行使）——两路独立追认，波 1 代码面证据链无反证。
3. **D-6 error 级定级（两路独立表态成立）**：用户常规工作流（重开项目）
   编辑器完全不可用 + 主线程 spin（电量/交互双影响）+ 机检证据硬
   （sample 全帧 AG spin）+ 与波 1 D-1 修法隔离性亲证（两修法触面不交）
   + 对照组（同会话新建路径健康）排除环境全局劣化——登记不修纪律合规。
4. **D-2 收紧的隐性代价显式化（E2-2 采纳）**：automatic 恒 v8 使
   X-Trans/Quad-Bayer 机身失去 RAW 9 融合 demosaic+denoise 质量面——
   毒化下收紧是正确权衡（机制全 v9 文件同构 + beta 名单逐季扩张 +
   健全性门双向假阳假阴），UI 零改；本闭环批 AGENTS 增量节已补记（§挂账③）。
5. **skip +11 供件漂移 = 环境 prior 事件（非本批静默跳过）**：漂移时点
   先于批开工 5.5h（mtime 链亲证）；本批唯一供件级新法未出现在 skip 列表
   （executed 真跑）= 反向证明；供件域回填后自动收敛（§挂账④）。
6. **V17 批内抓修（门实现 bug 首跑即修）**：`%[a-zA-Z]+` 不覆盖 `@` →
   两 String-arg 键幻红——`SPEC_RE = %(?:@|[a-zA-Z]+)` 修复后转绿；
   教训入册（specifier 解析字符类必须含 `@` 显式位）；修复正确性由活树
   `edr_headroom_label`/`settings_lcr_size_mb` 两键全绿佐证（N3 注记 =
   幻红期无 transcript，过程证据缺口登记级）。
7. **资源处置两笔（§8.2 静默合规）**：D-6 spin 实例两度按 AGENTS 处置线
   杀（本会话自起实例）；探针/走查产物全落 /tmp 即弃域与 gitignored 证据
   域（L077 `$TMPDIR` 残留清扫纪律适用）。

## 授权记录（C 档 VALIDATION 落签）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8..M2-11 +
  M3/M4/M5/M6 全系 + 本 phase 两波执行/验收同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：V2/Maintenance 闭环批任务书明载
  「夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻）」——VALIDATION
  成文与翻账为同一授权链尾段。
- 依授权，本 VALIDATION 由 V2/Maintenance 闭环批 worker 落盘签核
  （`.work/config.toml [gsd] paused=false / auto=true` 全程未动，
  dual_acceptance 双路验收已先行落终态）；用户晨审可推翻本签核（推翻 =
  V2/Maintenance 签核作废回退，已交付面与四路执行/验收证据不受影响；
  翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode V2/Maintenance 闭环批 worker（2026-10-16）；
  **doc-only——零源码 diff**（工作树既有 untracked 兄弟批/孤儿域件
  〔M3-1-ACCEPTANCE-PI / retro-dual / dt-clone-archive / 四份 V2M
  ACCEPTANCE 本批随 commit 入库〕零触碰）。
- **呈报裁决点（禁静默）**：①下一修复批立项时机与范围（挂账①，D-6 首项
  ——默认 = 用户定向后立项）；②波 1 屏面四项走查批复走通道（挂账②，默认
  = D-6 修复后随批，通道 = AX+截图 harness）；③forceV9 显式档是否随
  修复批加面板警示（挂账③，默认 = 仅登记不改 UI——面板已有
  readout/downgrade 提示）；④RAW 供件备料归属（挂账④，用户侧）。

## 翻账与移交（本批同 commit）

- **AGENTS**：「V2-Maintenance 架构增量」节补波 1 四行（D-1 快照修法范式 /
  D-2 automatic 收紧裁定 + forceV9 遗留 + X-Trans 质量面退场 / D-5 Int 化
  先例 / 波 1 终值）+ 节尾追加 phase 闭环行（VALIDATION 正本指针 + 终态
  3857/35/0）；既有波 2 四行 + V2M-02 终值行零改写。
- **ROADMAP**：§Milestone 6 块后追加「V2/Maintenance 站」节（缺陷修复 +
  清算批 ✅ 闭环行，双波双路结论 + 执行链 + 终态 3857/35/0）；头部状态行
  追加 V2/Maintenance 站闭环句。
- **STATE**：current_phase 翻新 = V2/Maintenance closed → next 待用户定向
  （下一修复批立项 or M7 or 其他）；status 头部追加本批终态；
  total/completed_plans 154→156。
- **TODO**：V2/Maintenance research 行后追加闭环行（[x]）；「M6 收口走查
  缺陷登记」D-1..D-5 五行翻「代码面 fixed（commit 链），屏面证据挂 D-6
  修复后走查批」；新增 D-6/D-7/D-8 登记行（修复批入口）。
- **GOAL-STATE**：顶部续接点追加 = V2/Maintenance phase closed（VALIDATION
  signed + 终态 + 挂账六项）→ **续接点 = 待用户定向**（下一修复批立项
  or M7 charter or 其他）。
- 修批/执行链 `54124c7e..bb16f8c4` + `2ba1d1fe..08f9ebc4` 已在库；未 push；
  四份 ACCEPTANCE 文档随本批 commit 入库（local-only 证据域 gui-acceptance
  与 phases/*/evidence/ 不入 git 惯例维持）。

## 签核

- 五项 OQ 生效值（OQ-VM-1..5）+ 两波 AC 零回归门 + 数字门全项 **Delivered**
  （三列证据齐；数字对账 = 波 1 三路 3851/35/0 同值 + 波 2 终值
  3857/35/0，对账链 3848+3+6 = 3857 精确闭合；双重验收每波零实质分歧）。
- `status: validated` + `nyquist_compliant: true`。
- **V2/Maintenance（缺陷修复波 1 + 清算波 2）closed**：双波双路独立验收
  PASS / 0 error + 0 minor open，终验全套实测 `TOTAL|3857/35/0|`
  （skip 35 = 基线 24 + 供件漂移 11）；批内新缺陷三笔（D-6 error 级候选 /
  D-7 / D-8）登记不修转下一修复批（D-6 首项），波 1 屏面证据四项 + D-4
  复验延续至 D-6 修复后走查批硬义务；挂账单一清单六项（§挂账总汇编）移交
  下一修复批与晨审。
- 晨审裁决项：四项呈报裁决点（见授权记录）+ 签核推翻窗（原话授权在案）。
- **C 档 VALIDATION = 夜间授权先例落签，晨审可推翻。**
