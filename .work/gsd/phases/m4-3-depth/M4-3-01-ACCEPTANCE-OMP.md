# M4-3-01 二次验收报告（omp 独立第二遍）

结论头：**PASS / 0 error + 2 minor**

- 首验：zcode subagent，PASS / 0E+2minor（m-a 已修 `57596d3`；m-b 账面口径勘误）
- 本路：omp 独立复验，PASS / 0 error + 2 minor（o-1 账面口径注记沿用 m-b；o-2 复算余量注记，无代码影响）
- 日期：2026-10-10
- 基线：`d2e234a..0355e65` 十提交 + 首验批 `57596d3` + 落账 `d053a60`（本验 HEAD = `d053a60`）
- 方式：亲跑 + 独立复算（numpy + Swift 原文探针）+ 机检亲证，不转述 SUMMARY/首验

## 一、定向复跑（test-direct.sh 直启）

| bundle | 对表目标 | 本验亲跑 | 判定 |
|---|---|---|---|
| Layers | 411/3/0 | **411/3/0**（180s，peakRSS 1090MB） | 逐位 ✓ |
| Library | 626/4/0 | **626/4/0**（79s，611MB） | 逐位 ✓ |

- 两轮 exit 0 + 零 MEMFAIL（RSS 远离 8G 门）。
- Layers 411 = 基线 394 + 本批 17（DepthMaskPipelineTests 8 法 + DepthMaskEditingTests 9 法，`grep -c func test` 亲数）；Library 626 = 基线 619 + 7（Catalog/Store 增量）。增量与对账自洽。
- App bundle 未复跑（任务书只定向 Layers/Library；首验已覆 App 缺席/在场两态 + 挂账 #6 闭环）。
- 注：本机模型安装位缺席（`~/Library/Application Support/Lightamer/models/` 不存在）——App 门控法在本机为 skip 态，与本路复跑的两 bundle 无关（Layers/Library depth 法零模型门控；EditingTests 内 4 处 XCTSkip 均为环境门非资产门——zip 固件创建失败/Metal 缺席，本验两轮 3 skip 全基线身份成立）。

## 二、数学抽查（独立复算）

### 2.1 percentile linear 公式：numpy 全锚 + Swift 原文探针

- numpy 独立复算（非转抄测试值）：[1..10] q10=1.9/q95=9.55、[10,20,30,40] q10=13.0/q95=38.5、[5,5,5,5,9,9,9] q10=5.0/q95=9.0、[0,10] q25=2.5/q50=5.0——8/8 命中测试头注硬编码值（首验 10 锚含 [7] 单点双断言与 empty→nil，本验复算其数值子集全中）。
- Swift 原文探针（`percentile` 函数体逐字拷入单文件 `swiftc` 直编 + 运行）：8/8 在测试容差 `accuracy: 1e-6` 内 PASS。
- **o-2 注记（minor，无代码影响）**：`[1..10] q95` 一锚 Swift 侧 `got=9.549999` vs numpy 参考 `9.55`，`|d|=9.54e-07`——余量仅 4.6%（1e-6 门）。根因 = Swift 是 Float 域 lerp（`Float(rank-lo)` + f32 乘加），numpy 是 float64 域插值，9.55 在两域各落其最近邻（差 ~1 f32-ulp）。门值 1e-6 不是推导值是巧合值：恰够包住 1-ulp 跨域差。本验判定：当前全绿有效，但该锚本质是「跨域 1-ulp」测试而非算法测试——建议后续容差改为显式 f32-ulp 语义（如 `accuracy: 2 * Float.ulpOfOne * 10` 量级注记）或改 `Double(Float(x))` 比较纪律（L048）。不阻塞交付（纯测试面口径）。

### 2.2 两级靶 + 窗口边界

- 精确算术（Fraction）：n=4096、近区 419px（10.25%，m6 ≥10% 门）→ rank=3890.25、两邻居皆 0.9 → 精确 p95=0.9；近像素 relative=1.0 → 窗=(1−0.48)/0.22 钳 1 → α=1；远像素 relative=0 → α=0。与测试三断言同构。
- 守卫 (a) 通过：high−low=0.70 > max(1e-6, 1e-4×0.9)=9e-05 ✓。
- **numpy 上舍入伪影驳回**：首轮复算曾见 `P(v>=p95)=0.0`——后证为复算脚本侧 f64/f32 混排假象；亲核 `numpy p95 == input max` 逐位相等（ulp 差 0.0），Swift 侧 f32 lerp 同值。解析主张不受扰（见 §2.3）。

### 2.3 守卫 (b) 解析事实复核

- DECISIONS §3 主张：过守卫 (a) 的平面 `P(v≥p95)≥~5%` → 该批 α=1 → coverage≥5% ≫ 3e-4 → 默认参数下 (b) = NaN backstop only。
- 本验复核：成立，且可加强为严格论证——p95 定义 rank=0.95(n−1)，`hi=ceil(rank)≤n−1` 恒有 `sorted[hi]≥p95`（lerp 凸组合 ≤ max(lo,hi)），故至少 `n−hi ≥ n−1−0.95(n−1) = 0.05(n−1)` 个像素 ≥ p95（±1ulp 舍入只动边界相等像素，不动窗内 `relative≥0.70→α=1` 的批量——近像素 relative 恒钳 1，§2.2 亲算 `h+1e-9` 仍 α=1）。舍入伪影最多让 p95 高出 max 1 ulp，但窗函数在相对域是钳制形态，1-ulp 不改变任何批量覆盖结论。
- Lumen 侧：`selection.py:75→77` refine 在计数前（抹开高 α 故可达）+ `auto_masks.py:77` 0.0003 同值亲读——DECISIONS「Lumen 可达而我方不可达」机理陈述成立。

## 三、证据核对（资产链 + golden + perf + 键族）

- **digest 亲算**：磁盘 zip `shasum -a 256` = `3824a48c…d9da`、45,759,882 B——与 `ModelAssetDigests.generated.swift:93` sentinel 值逐位一致。
- **远端在册**：`gh release view ai-models-v1` 资产 `depth-anything-v2-small-f16.mlpackage.zip 45759882`——字节数与 digest byteCount 逐位一致（首验已做亲下载 SHA 复证，本验不再重复下载，以远端 size + 本地 SHA 双锚交叉）。
- **MANIFEST.sha256 亲验**：解包后 `sha256sum -c` **5/5 OK**（LICENSE/NOTICE/model.mlmodel/weight.bin/Manifest.json）；zip 条目 6 项与 DECISIONS §1 清单一致（+MANIFEST 自身）。
- **许可**：zip 内 LICENSE Apache 命中 4 处、NOTICE 3 处；NOTICE 头行即 Depth Anything 署名。manifest `licenseName == "Apache-2.0"` 由 CatalogTests 不变量钉死（首验亲读，本验信其读码 + 626 全绿背书）。
- **golden 数据**：`ref-f32.bin` 4,061,160 B = 5×815,232 恰整除；Python 独立解析 5 block 头全为 518×392、消费恰尽；README 门值表三在门（0.0023/0.0029/0.0036 + max-abs 上限 0.02）与 `DepthGoldenTests.swift:155/158` 门值字面一致；两排除件（horizon 0.0092 = 门 92%、ramp 0.0237 OOD）确为域/余量裁定非调门凑数（horizon 若入选仍过门——92% 余量卫生说成立）。
- **perf.md**：三档中位 45.0/55.8/67.0（N=5 全样本在案）+ 端到端 231.3ms；`.all` 显著快于 `.cpuOnly` = ANE 在档；冷专化 67.1 首轮注记诚实。本验未重跑探针（模型安装位缺席 + perf 非门值面；首验已独立亲跑 40.8/55.6/67.7/234.1 同带复证）。
- **零模型字节**：`git ls-files | grep -Ei 'mlpackage|mlmodel|weight.bin|zip$'` 零命中（注：首验命令含 `.zip` 字面多一个点，本验放宽为 `zip$` 仍零命中——更强）。
- **键族**：xcstrings depth 族 7 键在册（行 31050-31152）；`git diff d2e234a..HEAD -- xcstrings | grep -c '^-[^-]'` = 0（纯插入）；`zh-audit --check` **PASS**（1617 源键 / 1855 catalog = 首验 1848+7 全绿复证）。

## 四、读码抽查（worker / 协议 / 管线 / 可容性）

- **family 单源**：`ModelAssetCatalog.swift:117-120` 派生判别式（clip 先判优先序 doc comment 在册）；`testFamilyExhaustiveOverAllProfiles` 六 profile 穷举（2/3/1）+ 优先序断言 + `==` 新行折叠断言——亲读全文成立。
- **三腿分派**：`AIWorkerMain.open` `switch manifest.family` 三臂（clip 腿体 266-294 / enhancement 转发 / depth `openDepthLeg` 298-346）；`run` 420-423 `depthSessions` 命中 → `forwardDepthRun`（只读 inPath/outPath，run 级错误无 culprit）；crash hook（249-253）在资产解析之前 → depth 免费生效零改动。亲读成立。
- **协议零破坏**：`git diff d2e234a..HEAD -- AIWorkerProtocol.swift` = 0 行；envelope 测试 `testDepthEnvelopeRoundTripReusesPathChannel` 钉死 payload 键集恰 `{inPath, outPath}` + 外层零新键——亲读成立。
- **client 腿**：`runDepth`（260-279）与 `enhanceTile` 逐字段同构（withFallbackChain 包裹 + run 级 requestFailed 不耗链）；open 无 facts（manifest 静态形状单源）。亲读成立。
- **m3 isfinite**：`floatPlane` half（'L00h'/stride bytesPerRow/2）+ F32 双分支逐行读 + nonFinite 计数 → `nonFiniteOutput` typed；run 级 → `forwardDepthRun` catch → requestFailed（inferenceFailed 归因面）。亲读成立。
- **HEADLESS**：AIWorkerDepth imports = CoreML/Foundation/ImageIO/LightamerCore 四项（1-4 行亲读）；App 全仓 `MLModel(` 构造点仅 AIWorkerDepth + AIWorkerEnhancement 两文件（CLIP 经 InProcessMLModelRunner 封装——AC#3 grep 门亲跑成立）。
- **管线同构**：`DepthMaskPipeline.swift` 全文 116 行亲读——percentile（Double rank + f32 lerp）/ 归一钳制 / 窗 `(r−0.48)/0.22` / smoothstep `p·p·(3−2p)` / 守卫 (a)(b) 与 Lumen `selection.py:71-74` + `auto_masks.py:77` 逐行同构；1e-6 地板死代码注记诚实（checker o3 在案）。
- **inputShortEdge 可容性**：`init` 缺省 `= nil`（90 行）→ 五旧 profile 构造零改；`testFamilyExhaustive…` 上方 `shortEdge 全 nil` 零漂移负测亲见（152-164 行）；depth `(518,392)` 消费断言在 DepthSession init（101-102）与 `DepthMaskService.readDepthPlane` 调用点（289-290）同源——m2 全链落实成立。392 非 396 勘误：catalog 275 行 `inputShortEdge: 392` + 测试注记 "NOT the plan's transcribed 396" 双落。
- **红线抽检**：Sidecar/ 0 行、AIWorkerProtocol 0 行、全批 `.metal` 文件 0 个、V50Order/DrtRecord/HistoryStack/HistoryHash 0 行——`git diff d2e234a..HEAD` 亲跑成立（38 文件清单逐项在 front-matter 边界内；`LightamerApp.swift` 两行注入 DECISIONS §4 已申报）。
- **BUNDLE-MAP/Project.swift**：5 测试文件双登记亲见（MAP 11 行含 Depth 注释行；Project.swift +5 行）；`tuist generate` 尾闸由 Layers/Library 两轮直启成功旁证。
- **提交边界**：`d2e234a..0355e65` 十提交全 Conventional 全英文；验收批 `57596d3`（L074 重编号）+ `d053a60` 落账 docs-only。

## 五、与首验分歧点

1. **无实质分歧**：两路结论同为 PASS / 0 error；首验全部硬核主张（逐位对表、数学审计、资产 digest、协议零 diff、键族纯插入）经本验独立亲跑/亲算/亲读逐项复证成立。
2. **o-1（minor，沿用首验 m-b）**：执行批 SUMMARY §3 登记的 App 711/4/0 实为模型缺席态、其 skip 身份旁注错位——首验已勘误注记并补注 SUMMARY，本验认可该勘误（本机模型位缺席，本验以缺席态逻辑自洽确认：4 skip = 3 golden + 1 probe）。
3. **o-2（minor，本验新增，测试口径）**：`[1..10] q95` 锚余量仅 4.6%（f32-lerp vs f64-numpy 跨域 1-ulp 差 9.54e-07 vs 1e-6 门）——全绿有效但门值是巧合值非推导值。建议后续改显式 ulp 语义容差或 L048 `Double(Float(x))` 比较纪律。不阻塞交付。
4. **复算方法差异说明**：首验申报「10/10 数值锚逐位命中」——本验 Swift 原文探针确认 8/8 是「容差内 PASS」而非逐位相等（q95 锚差 1-ulp）。「逐位」措辞略强，实质（门内通过）成立。记 o-2 子项，不单独立项。
5. **覆盖差异**：本验未重跑 App bundle / perf 探针 / 远端亲下载（任务书定向 + 首验已覆 + 本机模型位缺席）；GUI 走查行（MANIFEST A-G）为 Manual-Only——本验以代码面（四态 gate/入口 id/commit 缝）读码代证，实机走查留用户侧。

## 验收结论

**PASS / 0 error + 2 minor**（o-1 账面口径沿用首验 m-b 已勘误；o-2 测试容差口径建议，无代码影响）。AC 13 条：AC#1-#12 经本验抽查面全成立（AC#7 的 (518,396) 字面按 392 勘误兑现）；AC#13 定向轮 Layers/Library 逐位全绿零 MEMFAIL，App/zh 面分别由首验与本验 `--check` PASS 覆核。
