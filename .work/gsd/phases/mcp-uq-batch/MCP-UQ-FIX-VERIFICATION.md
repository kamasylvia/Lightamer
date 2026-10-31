# MCP-UQ 修复轮终审验证（MCP-UQ-FIX-VERIFICATION）

> 终审员：zcode 独立眼（紧凑终审）。对象：`365bbe26`（omp 修复轮，
> `omp-fix.log` 终报 + DECISIONS「zcode review 修复轮」节）对
> `MCP-UQ-REVIEW.md` E-3 + m-1 的修复。复核基线 `2fb6d1a2..365bbe26`。
> 日期：2026-10-31。方法：只读 diff 核验 + 双向亲证独立复现（红/绿双轮
> 自行重跑）+ 定向回归 + 17 件封存面机检。

## 结论：PASS —— E-3 + m-1 修复亲证成立，双向亲证独立复现精确一致（红 30），批视为终态

全部核验项通过；修复报告无虚报（红轮 failures 数字经独立复现精确命中 30）。

## E-3 修复核

### 1. diff 形态 — 恰为单函数语义修正 ✓

`git show 365bbe26 -- App/Sources/Lightamer/MCP/Tools/McpSchemaCatalog.swift`：
`jsonValue` 唯一改动 = 删 `as? Bool` 首检 + NSNumber 分支内
`CFGetTypeID(n) == CFBooleanGetTypeID()` 判真布尔（真布尔 →
`McpJSON.bool(n.boolValue)`；其余 NSNumber 走原 int/double 路）。无其它
分支触碰、无签名改动、无行为面外溢——与修复方向逐字一致。产线逻辑改动
仅此一函数（McpOneShot.swift 的 usage 行为字符串改动另计，见 m-1 节）。

### 2. `as? Bool` 全仓唯一命中复核 — 无同族残留 ✓

全仓 grep（App/LightamerCore/LightamerIOP/Tests/Scripts）剩余命中全数
非同族：

- **生产面 5 处**（MaskRefineCoordinator/SessionState/
  CleanTerminateSentinel/AppPreferences/LibraryAnalysisService）：均为
  UserDefaults 读回——写入侧存真 Swift Bool（CFBoolean 座位），
  `as? Bool` 判型正确，与「JSONSerialization 数字桥接」族无涉。
- **测试面 ~30 处**：均作用于 `McpJSON.bool` 出口（真布尔）的解码比对，
  jsonValue 修后语义正确。
- 其余 1 处 = McpSchemaCatalog.swift:385 文档注释本身（禁形登记）。

### 3. 镜像断言独立性 — 真独立 ✓

`testDefaultsEqualTheEncodedDefaults` 重写后**期望侧全部为硬编码
字面量**（`.int(N)` / `.bool(...)`），不经 `jsonValue`/被测函数；被测侧
`field.defaultValue` 走生产合成路径。jsonValue 若复污，`bool(true) ≠
int(1)` 诚实变红——独立性成立（旧形态 `jsonValue(wire)` 镜像自洽已随
重写移除，diff 亲证）。五模块字面量逐字对照 Params init 默认值：

| 模块 | 测试断言 | Params init 实源 | 判定 |
|---|---|---|---|
| temperature | red/green/blue `.int(1)`；preset `.int(2)` | gains `Float = 1.0`；`preset = .user`（enum `user = 2`） | ✓ |
| exposure | exposure/black `.int(0)`；mode `.int(0)`；compensateExposureBias `.bool(false)`；compensateHilitePres `.bool(true)` | `0.0/0.0`；`mode = .manual`（`manual = 0`）；`false`；`true` | ✓ |
| colisa | contrast/brightness/saturation `.int(0)` | 三 `Float = 0` | ✓ |
| toneequal | 十 band `.int(0)`；blending `.int(5)`；method `.int(4)`；details `.int(4)`；iterations `.int(1)` | 十 band `= 0`；`blending = 5`；`method = .norm2`（`norm2 = 4`）；`details = .eigf`（`eigf = 4`）；`iterations = 1` | ✓ |
| equalizer | g0–g5 `.int(0)` | 六 `Float = 0.0` | ✓ |

直测 `testJsonValueTreatsZeroAndOneAsNumbers`：0/1 六种数字装（NSNumber
int/double ×4 + Swift Int 字面量 ×2）断言数值出口 + JSONSerialization
真布尔 true/false 两枚断言布尔出口——判型两臂全覆盖。

## 双向亲证复核 — 独立复现精确命中 ✓

修复报告称「新回归在旧 jsonValue 下 30 failures」。红轮日志未落盘，
终审**自行复现**：临时回退 `jsonValue` 函数体为旧形（`as? Bool` 首检 +
无判型 NSNumber 分支，逐字节 = `2fb6d1a2` 原文）→ 增量 build →
`McpGetSchemaTests` 定向 → **Executed 8 tests, 30 failures——精确一致**。
还原（`git checkout`，工作区零残留亲证）→ 重建 → 同套 **8/0/0** 绿。

红轮失败全量归类（30 条逐一核过，非抽样）：**零无关红，全部为数值/布尔
区分断言**——

- 镜像测试 26 条：temperature.red/green/blue + toneequal.iterations
  （`bool(true) ≠ int(1)`，即 1.0 → true 污染实锤）；exposure.exposure/
  black/mode + colisa 三项 + toneequal 十 band + equalizer g0–g5
  （`bool(false) ≠ int(0)`，即 0 → false 污染）。
- 直测 4 条：`__NSCFNumber 0 must be numeric, got bool(false)` ×2、
  `__NSCFNumber 1 ... got bool(true)` ×2（NSNumber 整形装 0/1/0.0/1.0
  四枚被旧 `as? Bool` 桥接截胡）。
- **反向验证（非红集）**：真布尔断言在旧码下原样通过（exposure
  compensateExposureBias/HilitePres `.bool` 两枚 + 直测 JSON true/false
  两枚）——红/绿边界精确落在 0/1 数字族，证明失败由 E-3 本体驱动，
  非断言写错导致的全盘红。

抽样 3 条失败断言逻辑核（任务要求）：temperature.red（期望 `.int(1)`，
1.0 默认 → true 污染 = review 实锤样本 #1）/ equalizer.g4（期望
`.int(0)`，0.0 → false 污染）/ 直测 `__NSCFNumber 0`（纯判型断言）——
三条均为数值/布尔区分断言，非无关红。

观察（非缺陷，不入修复义务）：直测六装中两枚 Swift Int 字面量（0/1）
经 `Any` 装箱后 `as? Bool` 动态判型不命中（Swift Int 动态类型非
Bool/NSNumber 桥接面），旧码下亦通过——判别覆盖实际由四枚 NSNumber 装
承担；六装作为「数值恒数值」钉仍全数有效。

## m-1 核（B-2/R2-M4 残留）✓

`McpOneShot.swift` usage 行 `list [--list]` → `list, --list`（旧写法
暗示 `mcp list --list` 合法而 parse 拒收）；`McpOnboardingTests.
testParseListAndHelp` 增 `XCTAssertTrue(McpOneShot.usage.contains("--list"))`
注记断言——两者 diff 亲证在位，绿轮该用例 passed。

## 定向回归复跑（guard 前置，`--monitor` 伴跑零告警）✓

| 项 | 结果 | 对账 |
|---|---|---|
| App bundle 全量（含 Mcp 族 18 类） | **1092/6/0**，peakRSS 1968MB，623s | review 轮 1091/6/0，+1 = 新增直测 |
| App Mcp 族 18 类合计 | **238/0/0**（类清单逐一对上 BUNDLE-MAP/Project.swift） | 修复轮申报 19 类 250/0/0 的口径差 = 类计数含 IOPP 腿；本值为一手复跑 |
| IOPParity `McpRenderParityTests` 定向 | **9/0/0**，peakRSS 3832MB（8G 门内），83s | 与修复轮申报一致 |
| McpGetSchemaTests（红→还原） | 旧 jsonValue **8/0/30 failures** → HEAD 重建 **8/0/0** | 双向亲证闭环 |
| zh-audit --check | **PASS**（1783 source / 2116 catalog / 10 interp） | 与修复轮/review 轮一致 |

机器注记：guard G4 贴线透明越门（Data 卷 14.5G < 25G 门，低于本批历轮
15.8–19.4G；本终审全程复用 HEAD 现势产物 + 单文件增量重建，磁盘消耗
微小；`--monitor` 伴跑全程零 RSS-KILL）。终审收尾时 build-for-testing
产物已重建回 HEAD 态，工作区 tracked 零改动。

## 封存面 17 件机检 ✓

`git diff 2fb6d1a2..365bbe26 --name-only` = 5 文件（DECISIONS /
McpOneShot.swift / McpSchemaCatalog.swift / McpGetSchemaTests.swift /
McpOnboardingTests.swift）。对 ARCHIVE 封存清单 17 件（DrtRecord /
TerminalTailPolicy / DrtTailAssembly / PixelPipe / Lut3dKernels.metal /
DrtEotf / ExportQueueContract / ExportFormatSpec / ImageIOEncoders /
WebPEncoder / NodeGraphCommand / LightamerSidecar / HistoryStack /
HistoryHash / PipelineDocument / V50Order / GradeCatalog）逐一 grep
diff 文件清单：**零命中**。

## 判定依据

- E-3 修复形态与 review 处方逐字一致；判型改 CFBoolean 身份判别，
  机理正确（真 Bool 与 JSON true/false 同为 kCFBoolean 实例，数字
  无论值均不是）。
- 独立复现的红轮 failures = 30 精确命中修复报告宣称值，且 30 条
  逐一归因 E-3（真布尔断言旧码下通过 = 边界精确）。
- 镜像断言期望侧硬编码、五模块字面量与 Params init 逐字一致——
  「独立断言不得经过被测函数」教训已落实。
- 回归全绿 + zh-audit PASS + 封存面零触碰。批终态成立，全套 `--all`
  由统一轮跑承接（零产线逻辑改动申报成立：仅 jsonValue 一函数判型 +
  usage 字符串行 + 测试/账本）。
