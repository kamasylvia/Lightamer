---
phase: m2-9
plan: "M2-9-01"
title: "数据模型与纯函数面（wave 1）——YiyinExportSettings 四模式扩容（Bounds/Print + upscale/cap + DPI 修正数学，Alcedo cpp:31-80/287-325 同构）+ 文件名模板引擎（12 字段 {token:arg} + 转义 + typed 错误 + sanitize 200 + fallback）+ 冲突三档（Increment 默认/FAIL/REPLACE）+ 元数据策略模型（7 bool + STANDARD/NONE）+ 命名模板预设模型（3 内置）——全部 additive，既有路径字节零漂移"
wave: 1
depends_on: []
autonomous: true
requirements: [M2EXP-01, M2EXP-02, M2EXP-03]
estimated_new_tests: 45
bundles: [Export, App]
files_modified:
  - LightamerCore/Sources/Foundation/YiyinExportSettings.swift   # 修改：OutputMode 加 bounds/physical 两 case + allowUpscale/maximumEdgePixels 字段（decodeIfPresent 容错）+ resolveExportResolution 纯函数（含 DPI 修正）
  - LightamerCore/Sources/Export/ExportRecipe.swift              # 修改：ExportVariant additive 字段（drtOutput/metadataPolicy/embedICC）+ derivedTag 新 case 补臂 + init 默认值；ExportFormatSpec/ExportColorSpace 两个枚举体零 diff
  - LightamerCore/Sources/Export/ExportFileNameTemplate.swift    # 新建：12 字段 token 解析/渲染/转义/typed 错误/sanitize/fallback（纯函数）
  - LightamerCore/Sources/Export/ExportMetadataPolicy.swift      # 新建：STANDARD/NONE 模式 + 7 bool + 固定剥离三项默认
  - LightamerCore/Sources/Export/ExportNamer.swift               # 修改：destinationURL 增 collisionPolicy 参数（默认 .increment = 现行为逐字节）
  - App/Sources/Lightamer/Export/ExportNamingTemplates.swift     # 新建：NamingTemplateStore（UserDefaults JSON 数组，键 export.namingTemplates + 3 内置 + 改名/删除）
  - Tests/LightamerTests/ExportFileNameTemplateTests.swift       # 新建【Export】
  - Tests/LightamerTests/ExportMetadataPolicyTests.swift         # 新建【Export】
  - Tests/LightamerTests/ExportCollisionPolicyTests.swift        # 新建【Export】
  - Tests/LightamerTests/YiyinExportSettingsTests.swift          # 修改：四模式/upscale 钳/cap/DPI 修正/解码兼容追加【Export】
  - Tests/LightamerTests/ExportRecipeTests.swift                 # 修改：新字段 additive 解码 + derivedTag 新臂追加【Export】
  - Tests/LightamerTests/ExportNamingTemplateStoreTests.swift    # 新建【App】
  - Project.swift                                                # 修改：新测试文件登记进 LightamerTestsExport / LightamerTestsApp 显式清单
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt   # 修改：新测试文件 bundle 归属登记（双登记闭环，M2-7-2 先例）
---

# Plan M2-9-01 — 数据模型与纯函数面（wave 1）

> **性质**：纯 additive 数据模型 + 纯函数 plan——**零行为变更**（消费面接线在 M2-9-02/03；
> 本 plan 交付的全部类型/函数在既有调用路径上字节不可达）。四块：①尺寸四模式扩容
> （M2EXP-01）；②文件名模板引擎（M2EXP-03 的引擎半边）；③冲突三档 + 元数据策略模型
> （M2EXP-02/03 的模型半边）；④命名模板预设（OQ-9 A，store 落 App）。规格锚点 =
> `M2-9-CONTEXT.md` 裁决记录（OQ-1..12 全按推荐生效）+ RESEARCH-NOTES §1（Alcedo
> file:line 实测）+ §3 差异矩阵 S1-S4/M1-M2/N1-N3 行。

## 已定裁决（硬约束，不得重开）

- **OQ-2（原地扩 YiyinExportSettings）**：`OutputMode` 加两 case（`bounds(w:h:)` /
  `physical(width:height:unit:dpi:)`——`print` 是 Swift 关键字避用，Alcedo 语义名
  PHYSICAL_SIZE）+ `allowUpscale: Bool = false` + `maximumEdgePixels: Int = 0`（0=关）。
  shortEdge/percent 保留不删（超集）。yiyin 面板 UI 本 plan 不动（三模式子集消费自然成立）。
- **OQ-4（模板语法全量移植）**：Alcedo `{token:arg}` 12 字段 + `{{`/`}}` 转义 + typed
  解析错误 + sanitize（`<>:"/\|?*` 与控制字符→`_`、首尾空格点剔除、Windows 保留名补
  `_`、stem 上限 200）+ fallback `"image"`；token 名大小写不敏感；sequence 实参必须
  全零数字（位宽编码在零个数里）；**shutter 渲染保持 `1-500` 分子-分母形态**（`/`
  是 macOS 文件名非法字符——与 Alcedo cpp:136-171 逐形态一致，执行时读该段对表）。
- **OQ-5（冲突三档默认 Increment）**：`ExportCollisionPolicy { increment, fail, replace }`，
  默认 `.increment` = 现 `-1/-2` 递增行为**逐字节**（含大小写不敏感占用比对）；FAIL =
  基名占用即 typed 抛错；REPLACE = 覆盖既有名。D-11-CONTEXT-4 为「扩档非换档」——
  DECISIONS 注记同步（不改写历史裁决文本）。
- **OQ-6（元数据模型 7 bool + UI 单开关后置）**：`ExportMetadataPolicy` =
  mode `{none, standard}` + exif/xmp/iptc 三 bool（默认 true）+ includeLocation/
  includeSerials/includeEditingHistory 三 bool（**默认 false = 剥离**）。XMP 编辑摘要
  packet 归 editingHistory 档（默认不嵌）——消费面在 M2-9-03，本 plan 只落模型。
- **OQ-9（v1 仅命名模板预设）**：3 内置对齐 Alcedo（`{source}` /
  `{date:yyyy MM dd}-{sequence:0000}` / `Export-{sequence:0000}`）+ 自存/改名/删除；
  存储 = UserDefaults JSON 数组，键 `export.namingTemplates`；**全 recipe 预设不做**
  （挂账 PRES 交汇）。
- **D-M2-9-CONTEXT-6**：Print 模式 DPI 缺失/非正 = typed 拒绝；
  `maximumEdgePixels` 对全部尺寸模式尾段生效，触发时 **DPI 随宽度比例同步修正**
  （保物理打印尺寸一致——Alcedo cpp:74-78 数学语义，golden 钉死）。
- **尺寸域**：像素域沿用我方 `1...100_000`（maxTargetPixels，超 Alcedo UI 的
  256..16384）；DPI 域沿用 `1...2400`（D-6 既有旋钮面保留）；物理尺寸域
  `0.01...100_000`（Alcedo QML:916 同域）。差异记 DECISIONS（模型域为准）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 尺寸解析单源 `resolveExportResolution`（Alcedo hpp:40-50 同构）

- 新纯函数 `YiyinExportSettings.resolveExportResolution(canvasWidth:canvasHeight:) ->
  ExportResolutionResult`（`success: Bool` / `width/height: Int` / `dpi: Int` /
  `message: String?`——typed 失败不抛，调用方裁决）。数学：
  1. `ScaleIntoBox`（cpp:31-61）：fit-inside `scale = min(wMax/wSrc, hMax/hSrc)`；
     `!allowUpscale` 时 `scale = min(scale, 1.0)`；`llround` 取整 + clamp `[1, …]`。
  2. `ApplyMaximumEdgeLimit`（cpp:63-80）：`max(w,h) > maximumEdgePixels`（>0 时）按
     box 再缩，**DPI 乘同比例**（宽度比例守恒 → 物理打印尺寸一致）。
  3. 模式分派（cpp:287-325）：original 直通（dpi=max(0,dpi) 语义 → 我方域钳
     1...2400）；longEdge = ScaleIntoBox(p, p)；bounds = ScaleIntoBox(w, h)；
     physical = **dpi ≤ 0 → success=false**（typed），像素 = physical/unitsPerInch ×
     dpi 再 fit-inside；**maximumEdgePixels 尾段全模式生效**（cpp:324）。
- 既有 `targetSize` **保留签名与返回值语义**，改为委托 resolve（丢 dpi）——既有调用
  面（ExportRenderer:214 / ExportRecipeTests 向量）零改动零漂移；M2-9-02 的 renderer
  切换到 resolve 拿修正后 DPI。shortEdge 走同族数学（我方超集，Alcedo 无此模式——
  upscale 钳与 cap 尾段同样生效）。
- `ExportRecipe.effectiveSizing`（percent fold）不动——fold 产物仍是 longEdge 模式的
  `YiyinExportSettings`，新数学自然覆盖。

### KD-2 additive Codable 纪律（v6/v7 sidecar 先例）

- `OutputMode` 新 case = enum additive（旧 rawValue 解码不破坏）；`allowUpscale`/
  `maximumEdgePixels`/ExportVariant 新字段全部 **decodeIfPresent + 默认值**（synthesized
  Codable 会炸旧 payload——必须手写 `init(from:)`，YiyinExportSettings 现无自定义
  decode，补之；ExportVariant 同法）。测试钉：旧 JSON 字面（三模式、无新键）解码
  逐字段等于新默认。
- **ExportVariant 新字段**（本 plan 只落载体，消费在 02/03）：
  - `drtOutput: DrtRecord? = nil`——nil = legacy 五空间路径（既有测试/legacy sheet
    全量字节冻结的锚）；非 nil = DRT 强制联动档（M2 UI 恒设；含 space/EOTF/peak
    三元组 + 渲染载荷，M2-9-02 消费）。`init` 的 `colorSpace` 参数补默认 `.sRGB`
    （additive——DRT 档下该值被忽略，仅 legacy 兼容载体，DECISIONS 记录）。
  - `metadataPolicy: ExportMetadataPolicy = .standard`（类型默认 = STANDARD 剥离三项）。
  - `embedICC: Bool = true`（Alcedo ExportIccPolicy EMBED 默认；false = OMIT，
    M2-9-03 编码消费）。
- **ExportFormatSpec 与 ExportColorSpace 两个枚举体 = 本 plan 封存面**：文件可改
  （同文件 additive 字段），但两枚举体内**零 diff**（git diff 逐 hunk 机检）。

### KD-3 模板引擎形态（`ExportFileNameTemplate.swift`，Core 纯函数）

- `ExportFileNameContext`（求值上下文，Alcedo hpp:102-115 同构）：`sourceStem` /
  `captureDate: Date?` / `cameraMake/cameraModel/lensModel: String?` / `iso: Int?` /
  `aperture: Double?` / `shutterSeconds: Double?` / `focalLengthMM: Double?` /
  `rating: Int?` / `sequence: Int`。字段渲染语义照 RESEARCH §1.4 逐条（ISO 0→空串、
  aperture 1 位小数、focal 1 位小数 + `mm`、rating clamp 0-5、sequence 按位宽补零、
  date 默认 `yyyyMMdd`、token 表 yyyy/MM/dd/HH/mm/ss——ICU 兼容直通）。
- 解析产物 = `ExportFileNamePart` 数组（literal/token 二态），**解析与渲染分离**
  （面板可先解析报错禁用 startExport——Alcedo QML:64 同构；渲染逐 job 调）。
- `sanitizedStem` 200 字符帽与 Windows 保留名是**模板渲染专用** sanitize（Alcedo
  cpp:183-197）；`ExportNamer.sanitizedStem`（APFS 宽容版）保持不动——两套策略并存，
  命名空间区分（`ExportFileNameTemplate.sanitizedStem` vs `ExportNamer.sanitizedStem`），
  DECISIONS 记录差异理由（模板名跨平台交换 vs 既有 stem 就地导出）。
- 命名模板预设模型 = `NamingTemplate { id: UUID, name: String, pattern: String,
  isBuiltIn: Bool }`（Core 定义）；store 落 App（KD-4）。

### KD-4 NamingTemplateStore（App 层，ImportDefaults 先例）

- `App/Sources/Lightamer/Export/ExportNamingTemplates.swift`：UserDefaults JSON 数组
  键 `export.namingTemplates`；内置 3 条**不入库**（枚举常量单源，UI 拼接展示）；
  用户预设全量替换语义写回 + `rename(id:to:)`（Alcedo replacedName 语义 = 改名即
  覆写）+ `remove(id:)`；body 零 UserDefaults 直读（M2-1 D-EXEC-1 注入式惯例——
  store init 注入 `UserDefaults`，测试注入 isolated defaults）。
- AGENTS.md UserDefaults 键登记由 M2-9-05 收口批统一补册（本 plan 不动 AGENTS.md）。

### KD-5 穷举 switch 影响面全列（FilterSQL L 系纪律——加 case 前必做）

`OutputMode` 加两 case 编译期炸出的穷举 switch 全列（执行时 `grep -rn
"case .longEdge"` 复核补全，结果入 DECISIONS）：
1. `YiyinExportSettings.validate` / `targetSize`——本 plan 改写（01 内）。
2. `ExportRecipe.derivedTag`（:144-155）——本 plan 补臂：`bounds` → `"WxH"`
   （如 `2048x1536`）、`physical` → 格式名 fallback（与 original 同法）。planner
   裁决，DECISIONS 记录。
3. `ExportPanelView`（App，`ExportPanelViewSizingKind` 映射臂）——**编译性补臂**
   （新 case 不可达臂，legacy 面行为字节冻结）；除该补臂外 ExportPanelView.swift
   **零 diff**（逐 hunk 机检）。
4. yiyin 面板消费面（执行时 grep 定位）——同款编译性补臂纪律。

## read_first

1. `.work/gsd/phases/m2-9-export/M2-9-CONTEXT.md`——裁决记录节（OQ-1..12 生效值）+
   decisions D-1..D-6。
2. `.work/gsd/phases/m2-9-export/RESEARCH-NOTES.md` §1.1/§1.2/§1.4——Alcedo
   recipe/尺寸数学/模板语义 file:line 正本；§3 差异矩阵 S1-S4/M1/N1-N3。
3. `LightamerCore/Sources/Foundation/YiyinExportSettings.swift` 全文——现模型 +
   maxTargetPixels/dpiRange 域 + targetSize 数学。
4. `LightamerCore/Sources/Export/ExportRecipe.swift` 全文——variant 面与 L013 无哈希
   红线 + derivedTag；`ExportNamer.swift` 全文——递增语义与大小写不敏感比对。
5. Alcedo 参考源（只读，GPL 不抄码）：`alcedo_studio/src/include/io/image/export_recipe.hpp`
   + `src/io/image/export_recipe.cpp`（:31-80 尺寸数学 / :136-171 字段渲染 /
   :183-197 sanitize / :210-259 token / :287-325 resolve / :376-422 解析错误）。
6. `Tests/LightamerTests/ExportRecipeTests.swift` + `YiyinExportSettingsTests.swift`——
   零漂移基线（effectiveSizing 向量 + targetSize 向量逐条保绿）。

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits 全英文、subject ≤72 字符祈使
   句、body 写 what+why）；只 add 申报文件；**不 push**；多段 message 用 `-F`（L040）。
2. **测试纪律**：新测试全部进 Export/App bundle（Project.swift + BUNDLE-MAP 双登记）；
   每任务边界跑受影响 bundle；全套回归基线 = **2577/16/0**（M2-8-3 终态）。
3. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
4. **零行为红线**：既有调用路径字节不可达——`ExportFormatSpec`/`ExportColorSpace`
   枚举体零 diff；`ExportNamer` 默认参数路径输出与现行为逐字节同（既有
   ExportNamerTests 零修改全绿）；`targetSize` 三既有模式输出向量零漂移。
5. **GPL 纪律**：Alcedo 源只读对标行为语义，代码不复制入库（自写实现；NOTICE 面不
   动——语义/数学对标在既有先例形态内）。
6. **收口核对**：每任务 `git diff --stat` 与 front-matter 逐文件核对，越界 = 违约。

## Tasks

### T1 尺寸四模式扩容 + 解析数学（KD-1/KD-2）

- **read_first**：上列 1/2/3/5/6。
- **action**
  1. `YiyinExportSettings`：OutputMode 加 `bounds(w:h:)` / `physical(width:height:
     unit:dpi:)`（`ExportPhysicalUnit { inches, centimeters, millimeters }` 嵌套枚举）
     + `allowUpscale`/`maximumEdgePixels` 字段 + 手写容错 decode + validate 扩展
     （physical dpi 必填域、bounds 像素域、cap 域）。
  2. `resolveExportResolution` 纯函数（KD-1 三步数学）+ `ExportResolutionResult`；
     `targetSize` 委托改造（三既有模式向量零漂移为门）。
  3. 测试：四模式 × upscale 钳 × cap 尾段 × DPI 修正锚（如 3000×2000@300dpi cap
     2000 → 宽度比例 2/3 → dpi 修正 200——golden 数值钉）+ physical DPI 缺失 typed
     失败 + 旧 payload 解码兼容 + 既有向量回归。KD-5 影响面 grep 复核入 DECISIONS。
- **验收标准**
  - [ ] 四模式数学 golden 全绿（含 DPI 修正锚 + fit-inside/upscale 钳/cap 三要素）；
        physical DPI≤0 = success=false typed。
  - [ ] 旧 JSON payload（三模式无新键）解码 = 新默认字段值（测试钉）；既有
        ExportRecipeTests/YiyinExportSettingsTests 零修改全绿。
  - [ ] `git diff` 中 ExportFormatSpec/ExportColorSpace 枚举体零 diff。

### T2 文件名模板引擎（KD-3）

- **read_first**：上列 2/5 + RESEARCH §1.4。
- **action**
  1. 新建 `ExportFileNameTemplate.swift`：`parse(_ pattern: String) -> Result`（typed
     错误集：未闭合花括号/未知字段/空模板/sequence 实参非全零数字/date 实参非法
     token）、`render(parts:context:) -> String`、`sanitizedStem`（200 帽 + Windows
     保留名）、fallback `"image"` 面。
  2. 测试：12 字段逐 token（含大小写不敏感 + `{date:yyyy MM dd}` 自定格式 +
     `{sequence:0000}` 位宽）+ `{{`/`}}` 转义 + 错误集逐条 + 渲染语义锚（ISO 0 空
     串/aperture-focal 1 位小数/rating clamp/shutter `1-500` 形态对照 Alcedo
     cpp:136-171）+ sanitize 全族 + 空渲染 → fallback。
- **验收标准**
  - [ ] 解析/渲染/转义/错误/sanitize/fallback 全族测试绿；shutter 与 Alcedo
        cpp:136-171 逐形态一致（DECISIONS 记录对照结论）。

### T3 冲突三档 + 元数据策略模型 + Variant 载体（KD-2）

- **read_first**：上列 1/4 + RESEARCH §1.1。
- **action**
  1. `ExportNamer.destinationURL` 增 `collisionPolicy: ExportCollisionPolicy =
     .increment`（默认路径逐字节=现行为）；`.fail` = 基名占用抛 typed；`.replace` =
     直接返回既有名路径。`ExportCollisionPolicy` 枚举落 ExportNamer.swift 或模板
     文件（落点执行定，单源即可）。
  2. 新建 `ExportMetadataPolicy.swift`（OQ-6 模型全量 + `.standard`/`.none` 便利
     常量 + 固定剥离三项默认）。
  3. `ExportVariant` additive 字段（KD-2 三件 + init 默认值 + 容错 decode）+
     derivedTag 补臂（KD-5 第 2 条）。
  4. 测试：三档语义（increment 与现递增 E2E 语义同源/occupancy 大小写不敏感保留）+
     政策模型默认值钉 + variant 新字段解码兼容 + derivedTag 新臂。
- **验收标准**
  - [ ] `ExportNamer` 默认参数既有测试零修改全绿；三档新测试绿。
  - [ ] `ExportMetadataPolicy` 默认 = STANDARD ∧ location/serials/editingHistory
        均 false（测试钉）。
  - [ ] ExportVariant 旧 JSON（无新键）解码兼容测试绿。

### T4 命名模板预设 store（KD-4）

- **read_first**：上列 1 + App 侧 `ImportDefaults` 先例（`App/Sources/Lightamer/
  Library/ImportModeDialog.swift` 或 ImportPreferences 文件——注入式惯例对表）。
- **action**
  1. 新建 `App/Sources/Lightamer/Export/ExportNamingTemplates.swift`（模型引用 Core
     `NamingTemplate`；store 三内置常量 + CRUD + 注入式 defaults）。
  2. 测试【App】：内置 3 条拼写与 Alcedo QML:35-52 一致（`{source}` /
     `{date:yyyy MM dd}-{sequence:0000}` / `Export-{sequence:0000}`）+ 存/改名/删除
     round-trip + 损坏 JSON 降级空库。
- **验收标准**
  - [ ] store 测试绿；UserDefaults 键拼写 = `export.namingTemplates`（源码常量单源）。

### T5 波次收尾核对

- **action**：`caffeinate -dis Scripts/test-direct.sh --bundle Export --bundle App`
  全绿 + 计数对账（基线 Export/App 分册 → 本 plan 增量 = front-matter 估计核对）+
  `git diff --stat` 逐文件对表 + DECISIONS 底稿落盘（KD-5 影响面清单 + shutter
  对照 + 尺寸域差异 + colorSpace 默认值注记）。
- **验收标准**
  - [ ] Export/App 两 bundle 0 fail；新增文件全部双登记（Project.swift + BUNDLE-MAP）；
        diff 边界 == front-matter。

## 验收标准（AC 总表，逐条可机检）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 四模式数学 golden 全绿（fit-inside/upscale 钳/cap/DPI 修正锚/physical typed 失败） | 测试名清单 + bundle 行 |
| 2 | 旧 payload 解码兼容（YiyinExportSettings/ExportVariant 两侧）| 测试名 |
| 3 | 既有 ExportRecipeTests/YiyinExportSettingsTests/ExportNamerTests 零修改全绿（targetSize 向量 + 递增行为字节零漂移） | `git diff` 零 hunk + 测试绿 |
| 4 | 模板引擎 12 字段/转义/typed 错误/sanitize(200)/fallback 全族绿；shutter=Alcedo 形态 | 测试名 + DECISIONS 对照记录 |
| 5 | 冲突三档语义绿（默认 .increment 逐字节） | 测试名 |
| 6 | 元数据策略默认 = STANDARD 剥离三项；7 bool 全量在模型 | 测试名 |
| 7 | NamingTemplateStore 三内置拼写一致 + CRUD round-trip；键 = export.namingTemplates | 测试名 + 源码 grep |
| 8 | 新测试文件 Project.swift + BUNDLE-MAP 双登记；Export/App bundle 0 fail | 两文件 grep + bundle 行 |
| 9 | ExportFormatSpec/ExportColorSpace 枚举体零 diff；ExportPanelView 仅编译性补臂 | `git diff` 逐 hunk 审 |

## 风险与边界

- **穷举 switch 漏列**（L 系教训）：KD-5 清单是 grep 起点，执行期以编译错误为完整
  集合仲裁——每个新臂入 DECISIONS 清单；禁止 `default:` 息事（穷举纪律）。
- **Alcedo 语义偏差**：我方超集面（shortEdge/percent/2400dpi 帽）与 Alcedo 字面域
  的差异全部落 DECISIONS 对照表，不静默吞。
- **Codable 容错遗漏**：synthesized decode 混入 = 旧 payload 解码炸——T1/T3 测试
  强制旧 JSON 字面锚（E2 纪律：测试可观测非口头保证）。

## 提交约定

- T1 `feat(m2-9): export sizing four-mode model with dpi-corrected resolution math`
- T2 `feat(m2-9): alcedo-style export filename template engine`
- T3 `feat(m2-9): collision policy tiers, metadata policy model, variant carriers`
- T4 `feat(m2-9): naming template preset store`
- T5 `test(m2-9): wave-1 bundle reconciliation`
- 全英文；body 写 what+why；不 push。
