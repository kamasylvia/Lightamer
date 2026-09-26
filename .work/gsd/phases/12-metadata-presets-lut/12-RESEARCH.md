# Phase 12 Research — Metadata, Rating, Presets & LUT

**Date:** 2026-09-26
**Status:** Complete — 8 研究问题全答；XMP 头项探针实测通过（改变 12-3 plan 形态）；DB v2 列集冻结建议已出
**Inputs:** 12-CONTEXT.md（D-12-CONTEXT-1..10 逐条落实）、ROADMAP §Phase 12、REQUIREMENTS META/PRES/IOP-COLOR-08/MCP-05..09、Phase 9 交付面（SessionIndexSchema/SessionIndexStore/LightamerSidecar/PastePayload/SessionBatchApplier 源码级核对）、Phase 11 移交五条 + ExportRecipe 源码、dt 只读参考（lut3d.cl/.c、tags.c、collection.h/.c、iop_order.c 源码级核对）
**方法：** 本机 macOS 27（Build 26A428）swift 一次性探针 ×2（/tmp，跑完即弃）+ sqlite3 10k 行 LIKE 实测 + SDK header 逐条 grep + dt 源码逐行读

---

## §0 结论速览（与 CONTEXT 的差异修正表）

| # | 发现 | 对 CONTEXT 的影响 |
|---|---|---|
| F1 | **`CGImageMetadataCreateXMPData` 本机可用**：产出 831 字节合法 XMP packet（x:xmpmeta/rdf:RDF + xmp:Rating + xmp:Label + dc:subject(rdf:Bag) + lr:hierarchicalSubject(rdf:Bag)），`CGImageMetadataCreateFromXMPData` round-trip 值全对 | D-12-CONTEXT-2 案 A 的「优先验证」分支**成立**；「手写 XMP writer」分支死；12-3 自建序列化 = **薄封装**（约百行级），工作量较 discuss 预估下降 |
| F2 | 自定义 namespace（lr）必须先 `CGImageMetadataRegisterNamespaceForPrefix` 再 SetTagWithPath，否则 set 返回 false；dc:subject 直塞 CFArray 会序列化成 **rdf:Seq**（非惯例 Bag）——必须 `CGImageMetadataTagCreate` + `.arrayUnordered` 才得 rdf:Bag | 12-3 技术前提补两条（CONTEXT 未载）；XMP 生态 dc:subject=Bag 惯例保住 |
| F3 | 层级关键字祖先过滤若用裸 `LIKE '%Nature%'` 会误命中含 "Nature" 子串的兄弟标签（如 `NatureHolics`）；**四联式**（`=` / `x\|%` / `%\|x\|%` / `%\|x`）语义精确且 10k 行实测同量级（0.95ms vs 0.37ms） | D-12-CONTEXT-3 的谓词形态建议修正为四联式（语义不变、实现更准） |
| F4 | dt `lut3d.c:782-791` 的解析器**只支持 DOMAIN 0..1**（DOMAIN_MIN≠0 / DOMAIN_MAX≠1 直接报错拒绝）；Lightamer 裁决要求 DOMAIN remap = **超出 dt 能力面**（正向超出） | D-12-CONTEXT-6 可行，但 remap 公式与精度论证为本 research 补齐（§6.3/§6.4） |
| F5 | DB v2 列集全下游扫描结论：25+9=**34 列冻结**（flag/note + EXIF 七列）；MCP-05/06/07/09、Phase 13 Spotlight/QuickLook、culling 聚类全覆盖；aspect_ratio 等可导出列**不进**列集 | D-12-CONTEXT-1 reversibility 条款兑现（一次到位复核完成） |
| F6 | 元数据写路径的 crash 一致性精细分析：段2 必须**同步写新 sidecar_mtime + dirty=1**（且**不动 thumb_state**），段3 落盘后 clearDirty；否则 crash 窗口出现「索引已打分、sidecar 未写、mtime 已新」的三态漂移且下次 open 不自愈 | D-12-CONTEXT-8 的机制面补丁（详见 §2.4）；`claimBatchApply` 本体不可复用（它会 stale thumb），需新写 `claimMetadataApply` |
| F7 | Phase 9 freeze 契约的两个 additive 扩展点在 Phase 12 必改：`backfillSidecarSummaries` / `healDirtyRows` 的 UPDATE 列集需加五元数据列（否则 crash heal 回填时丢评分列） | Phase 9 函数签名不变、UPDATE 语句 additive——不破契约，plan 里必须列为任务项 |

---

## §1 XMP 序列化探针（头项实验，DONE）

### 1.1 实验设计

swift 一次性脚本（/tmp，已弃）：构造含 `xmp:Rating` / `xmp:Label` / `dc:subject`（数组）/ `lr:hierarchicalSubject`（自定义 namespace 数组）的 `CGMutableImageMetadata` → `CGImageMetadataCreateXMPData` → 字节断言 + `CGImageMetadataCreateFromXMPData` round-trip 值断言。

### 1.2 结果（macOS 27.0 Build 26A428，Xcode MacOSX.sdk）

**可用。** 序列化输出（v5 探针实测，831 字节）：

```xml
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0.0">
   <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/">
         <xmp:Rating>3</xmp:Rating>
         <xmp:Label>Green</xmp:Label>
         <lr:hierarchicalSubject><rdf:Bag><rdf:li>Nature|Flower|Rose</rdf:li>…</rdf:Bag></lr:hierarchicalSubject>
         <dc:subject><rdf:Bag><rdf:li>Rose</rdf:li><rdf:li>Flower</rdf:li></rdf:Bag></dc:subject>
      </rdf:Description>
   </rdf:RDF>
</x:xmpmeta>
```

round-trip：rating/label 全对；`lr:hierarchicalSubject` 解析回 tag 数组，item 值 `Nature|Flower|Rose` / `Nature` 完整。空 metadata 序列化返回 **nil**（合法行为——无字段不产 packet，writer 需处理）。

### 1.3 实测确立的 API 面（SDK header 逐条核对）

| 用途 | API | 备注 |
|---|---|---|
| 构造字段值 | `CGImageMetadataSetValueWithPath`（标量） | 内置 namespace（xmp/dc）直用 |
| 构造受控数组 | `CGImageMetadataTagCreate(xmlns, prefix, name, type, value)` + `CGImageMetadataSetTagWithPath` | `type: .arrayUnordered` = rdf:**Bag**；`.arrayOrdered` = rdf:Seq；**直塞 CFArray 到 SetValueWithPath 产 Seq 且 namespace 不可控——禁止** |
| 自定义 namespace | `CGImageMetadataRegisterNamespaceForPrefix(&err)` | 不注册则 SetTagWithPath 返回 **false**（v4 探针实测） |
| 序列化 | `CGImageMetadataCreateXMPData(metadata, options)` | header `CGImageMetadata.h:616`，avail 10.8+ |
| 解析（只读导入用） | `CGImageMetadataCreateFromXMPData` + `CGImageMetadataCopyStringValueWithPath` / `CopyTagWithPath` + `CGImageMetadataTagCopyValue` | |
| **不存在的 API** | `CGImageMetadataCreateTag` / `CGImageMetadataCreateArray` / `CGImageMetadataCopyValueWithPath` 均不在公开 header | 网上旧文档名不可信，以本表为准 |

### 1.4 对 12-3 plan 形态的裁决

- **`XMPWriter`（新，Core 级）= ImageIO 薄封装**：`fields → Data`。字段面：`rating: Int?`（0-5；reject=−1 惯例）、`label: String?`（colorLabel Int → 色名字符串映射表）、`hierarchicalSubject: [String]`（`|` path 全量）、`subject: [String]`（叶子扁平去重）。纯函数 + golden 可测。
- 11-02 D3 的宿主事实**修正表述**：死的是「**ImageIO 写端**（properties dict → 文件字节）五途径」；**序列化端活着**。XMP packet 生成不手写 XML 模板（原 +1 天工作量分支作废），12-3 的实现重心全部落在 **per-format 容器注入缝**（§8.2）与 golden。
- fallback（若未来宿主移除此 API——可能性极低）：XMPWriter 内部换 XML 模板实现，接口不变。插件位保留（D-2 reversibility 兑现）。

---

## §2 sidecar v3 + DB v2 迁移规格（12-1 核心）

### 2.1 sidecar v3 additive 五字段（照 `LightamerSidecar.swift` v2 layerStack 先例）

```swift
public static let schemaVersionCurrent = 3        // :102 处升版
public var rating: Int?       // 0...5, nil = 未评分
public var flag: Int?         // 0=none / 1=pick / 2=reject（MCP-06 语义）
public var colorLabel: Int?   // 0...6（C1 七色）
public var keywords: [String]? // 完整层级路径数组，"|" 分隔（§3）
public var note: String?
```

- decode：`decodeIfPresent`（v2 文件降级读，`:334` additive 模式照抄）；encode：`encodeIfPresent`（恒写或 nil 省略——建议 `encode` 恒写与 CONTEXT「encode 恒写」一致时用 `encode`，nil 时写 null 亦可；**plan 期定死一种**，golden 锁）。
- schema 依赖投影：`if schemaVersion >= 3 { … }` 分支模式同 layerStack（`:222-228`）；`schemaVersionCurrent` 升 3，reader 容忍 `> 3` 契约（`:94-97`）**不动**。
- **关键约束：五字段不进 `driftDetected` 哈希**（`HistoryHash.hash(stack:decodeParamsHash:layerSnapshot:)` 不变）——元数据不是管线参数，改评分不得触发 drift false-positive（D-12-CONTEXT-1「不翻 paramsHash」的字节面推论）。`sidecar v3 写 → historyHash/paramsHash 逐字节不变`必须成为测试断言。
- init 签名加带默认值参数（`rating: Int? = nil, …`）——既有调用点零改动。

### 2.2 DB v2 迁移序列（首次真迁移）

新增列（9，全部尾追加，SQLite `ALTER TABLE ADD COLUMN` 只能尾列 + NULL 初值天然满足）：

```
flag INTEGER, note TEXT, camera_make TEXT, camera_model TEXT, lens_model TEXT,
iso INTEGER, focal_length REAL, aperture REAL, exposure REAL
```

- `imagesColumns` 冻结列表追加 9 条（25→34）；**Phase 9 的 `PRAGMA table_info` VERBATIM 断言测试同步更新到 34 列**（frozen-spelling 测试是既有资产，改期望值即可）。
- 迁移函数 `SessionIndexSchema.migrate(from:to:on:)`（表驱动）：
  1. `BEGIN IMMEDIATE`
  2. 读 `PRAGMA table_info(images)` 已有列集，**逐列幂等防御**（列已存在则跳过——二次迁移零害）
  3. `ALTER TABLE images ADD COLUMN …` × 9
  4. `UPDATE meta SET value='2' WHERE key='schemaVersion'`
  5. `COMMIT`
- `apply(to:)` version dispatch 改造（`SessionIndexSchema.swift:145-167` 模式上扩展）：absent → 直接建 v2 DDL + stamp 2；`1` → migrate to 2；`2` → ok；`>2` → REFUSE（v99 拒开语义保留）。EXIF 七列初值 NULL，由 `backfillExifMetadata` 的 NULL-class 机制既有路回填（`SessionIndexStore.swift:757-760` 的 pending 谓词扩列即可）。
- **不建新索引**：10k 行全表扫描实测 <1ms（§3.4/§4.4），过滤谓词无索引收益，写放大不值。文档化决策。

### 2.3 v2 列集冻结复核（一次到位，F5）

| 下游 | 需求 | v2 覆盖 |
|---|---|---|
| MCP-05 list_photos | EXIF 轻量列/rating/flag/has_edits | ✓（七 EXIF 列 + rating/flag/has_edits 既有） |
| MCP-06 写面 | flag/note | ✓（新增两列） |
| MCP-07 culling | burst 聚类（拍摄时间+机型） | ✓（capture_date 既有 + camera_model 新增） |
| MCP-09 | set_keywords/list_presets | ✓（keywords 预留列） |
| Phase 13 Spotlight | rating/labels/keywords/EXIF | ✓ 全盖 |
| dt `collection.h:74-136` 属性枚举对齐面 | camera/lens/aperture/exposure/focal/iso/rating/colorlabel/tag/textsearch | ✓（textsearch = keywords LIKE，无新列） |
| 可导出维度（aspect_ratio/色域/文件类型） | 可由 width/height/文件名派生 | **不进列集**（宁少勿滥；v99 拒开兜未来） |

**冻结建议：34 列。** 二次迁移的代价（又一轮 ALTER + 全量 parity 测试）> 多一列空置；但「可派生列」不加——列集膨胀无回报。

### 2.4 元数据写路径的 crash 一致性（F6，D-8 机制面）

MetadataService 三段（9-4 同构）的索引段语义与 9-4 params 批量**不同**，精细面：

- 段2 `claimMetadataApply`（新方法，**不复用** `claimBatchApply`——后者 UPDATE 含 thumb stale + params_hash/has_edits/layer 列，全不适用）：
  ```sql
  UPDATE images SET rating=?, color_label=?, keywords=?, flag=?, note=?,
                     sidecar_mtime=?, dirty=1
  WHERE path=? AND orphan_sidecar=0
  ```
- 段3 落盘（BatchSidecarWriter 既有串行队列复用）→ `clearBatchDirty`（既有，:948 原样）。
- **为什么必须 dirty=1 + 同步写 sidecar_mtime**：若无 dirty，段2 与段3 之间的 crash 留下「索引已打分 / sidecar 未写 / sidecar_mtime 已标新」——mtime 漂移检测（`backfillSidecarSummaries` :643-658）判「无漂移」**不自愈**，删库重建即丢分（真身恒 sidecar 契约破）。dirty=1 时 `healDirtyRows`（:970）crash 后重读磁盘 sidecar **旧值回填**——状态一致、真身诚实（分确实没写进去）。
- **为什么不动 thumb_state**：评分不是参数变更，`thumb_params_hash` 不变即非 stale——万张打分零缩略图再生（D-8 性能陷阱红线）。断言：批量 setRating 后 `thumb_state` 逐行不变。
- 正常完成路径 dirty 清 0；`healDirtyRows`/`backfillSidecarSummaries` 的 UPDATE additive 扩五列（F7——从 sidecar 文档读出五字段回填，Phase 9 函数签名不变）。

### 2.5 EXIF 轻量七列回填

`backfillExifMetadata`（:755）既有路 additive：properties dict 取 `kCGImagePropertyExifDictionary`（`ISOSpeedRatings`/`FocalLength`/`FNumber`/`ExposureTime`）+ `kCGImagePropertyTIFFDictionary`（`Make`/`Model`）+ `kCGImagePropertyExifDictionary.LensModel`。pending 谓词从 `orientation IS NULL` 扩为 OR 任一新列 NULL（注意：无 EXIF 的图会产生「永远 NULL」行——谓词须带尝试计数或 mtime 判定防每次 open 重扫；**建议：pending 谓词保持 orientation 锚 + 新列走同批 UPDATE，无 EXIF 图置空串哨兵**——plan 期定）。QoS：后台、不阻塞首帧。

---

## §3 层级关键字（F3 修正落定）

### 3.1 模型

- sidecar `keywords: [String]?` 存完整 path（`"Nature|Flower|Rose"`）；打子标签**不物化祖先**（单一真身，语义在查询面展开）。
- DB `keywords` 列 = `keywords.joined(separator: "|")`（既有预留列，零 ALTER）。
- XMP：`lr:hierarchicalSubject`（Bag，path 全量）+ `dc:subject`（Bag，**叶子**扁平去重）双字段（v5 探针已实测两字段同 packet 共存）。
- 分隔符 `|` 入 XMP 即锁（dt `tags.c:817`「keep also tags in the path」+ Lr `lr:hierarchicalSubject` 同惯例；C1 同）。UI 录入禁 `|`（校验 typed error）。

### 3.2 祖先匹配谓词（四联式，F3）

按标签 `T` 过滤的精确 SQL（参数绑定）：

```sql
(keywords = ?1 OR keywords LIKE ?1||'|%' OR keywords LIKE '%|'||?1||'|%' OR keywords LIKE '%|'||?1)
```

裸 `LIKE '%T%'`（CONTEXT D-3 原文形态）误命中 `NatureHolics` 类子串兄弟标签——**修正为四联式**，语义 = dt 打子隐含父的同义重言。UI 展示的标签树 = 全库 path 前缀树投影（内存构建，10k 行 × 均 2 path = 微秒级）。

### 3.3 XMP 导入映射

`lr:hierarchicalSubject` Bag → path 数组直存；仅 `dc:subject` 的第三方文件 → 叶子升单级 path 直存（无祖先信息，诚实降级）。

### 3.4 性能实测（10k 行，sqlite3 实测）

| 查询 | 耗时 |
|---|---|
| `LIKE '%Nature%'` | 0.93ms |
| 四联式祖先匹配 | 0.95ms |
| 四联式 AND `rating>=3` 组合 | 0.71ms |
| camera+iso+flag 三条件组合 | 0.46ms |

**结论：万张规模 LIKE 全扫零压力**（≤5s 批量门用不到其 0.1%），无索引必要成立。

---

## §4 过滤/排序/智能相册（谓词 → SQL 单一翻译层）

### 4.1 谓词组 Codable schema（智能相册持久化面 + 过滤栏临时面同型）

```swift
struct FilterPredicateGroup: Codable {          // 智能相册文件体 / 过滤栏 state
    var schemaVersion: Int = 1
    var match: Match = .all                     // .all=AND / .any=OR（v1 不做嵌套组）
    var rules: [Rule]
    struct Rule: Codable {
        var field: Field    // rating/colorLabel/keywords/flag/note/cameraMake/cameraModel/
                            // lensModel/iso/focalLength/aperture/exposure/captureDate/
                            // hasEdits/filename/dir
        var op: Op          // eq/neq/gt/gte/lt/lte/between/in/contains/startsWith/empty/notEmpty
        var value: Value    // String|Int|Double|[String]|闭区间——tagged union Codable
    }
}
```

### 4.2 翻译层（单一函数）

`FilterSQL.translate(group:) -> (sql: String, binds: [Bind])`：

- 规则 → 括号化条件片段；`.all` = AND 连接 / `.any` = OR；空组 = `1=1`。
- 关键字走 §3.2 四联式；文本字段（filename/dir/note）`contains` = `LIKE '%'||?||'%'`（`LIKE` 默认对 ASCII 不区分大小写——够用；zh 无大小写概念）；数值区间 `BETWEEN ? AND ?`；`captureDate` 值 = epoch Double（UI 日期选择器折叠）。
- 参数全 bind，**零字符串拼接值**（dt `sqlite3_mprintf %q` 的 Swift 对应 = bind 机制，注入面关闭）。
- 排序 `ORDER BY ?` 不吃 bind——排序键白名单枚举直译列名（`filename/rating/capture_date/iso/focal_length/scan_epoch` × asc/desc，UserDefaults 持久化）。
- 基线谓词恒附加：`orphan_sidecar = 0`。

### 4.3 Quick Filter

行内搜索框 → 单条 `contains` 组（filename OR keywords 四联式任一命中）；`/` 聚焦、Esc 清除、快捷 chips（星级≥3 / pick）= 预填谓词组。纯翻译层消费，无新 SQL 面。

### 4.4 智能相册

- 存储：`~/Library/Application Support/Lightamer/SmartAlbums/*.json`（一规则一文件，sortedKeys + tmp 原子晋升，L009 模式）；启动重扫自愈 = YiyinFontStore 先例。
- 求值：点入 → 当前会话 `session.lindex` 上跑翻译层 SQL（D-4 求值域契约）；结果集随会话，规则随 app（解耦正本）。

---

## §5 预设容器 `.lightamer-preset`

### 5.1 格式（one-way 格式锁 + sortedKeys，L013 全适用）

```jsonc
{
  "schemaVersion": 1,
  "kind": "develop",              // "develop" | "export"（additive 枚举）
  "name": "Warm Film",
  "category": "Tone",             // 自由串；侧栏分组键
  "appVersion": "0.x.y",
  "createdAt": <Date default encoding>,
  "instances": [ …SidecarInstanceRecord 同拼写（paramsHash = decimal String，L013）… ],
  "layerStack": null,             // additive 预留位（蒙版语义未定义，defer）
  "exportRecipe": [ …ExportVariant 全量… ]   // kind=export 时；develop 恒 null/省略
}
```

- develop `instances` = **PastePayload compose 产物同构**（skip 集已应用：`PastePayload.compose` 的 ①decode 域边界 15.0 ②恒等默认 ③自动检测 verbatim 三规则原样——D-09-CONTEXT-5 正本零重写）。
- **L013 投影**：PastePayload 运行时 paramsHash 是 JSON number（进程内语义）；preset 是持久化字节 → 必须 `SidecarInstanceRecord` 同款 decimal-String 投影（internal 可见性同 target 可复用，或独立投影类型——plan 期定，拼写必须逐键一致）。
- `ExportRecipe`（`ExportRecipe.swift:105` typealias `[ExportVariant]`）已 Codable + 零哈希字段（移交①源码级核对通过：`ExportVariant` 全字段 sizing/scalePercent/format/colorSpace/yiyin/outputTag，无 hash）——直挂零迁移。

### 5.2 apply 路径（与 9-4 paste 同构复用清单）

| 步骤 | preset apply | 9-4 paste 复用点 |
|---|---|---|
| 读文件→payload | `PresetsStore.load` → `PastePayload(sourceImageID: UUID(), sourceURL: nil, instances:, layerStack:, copiedAt: 文件时间)` | PastePayload 值类型直构 |
| 段1 | `SessionBatchApplier.composeSegment(payload:mode:)`（:70 签名原样；live 保护/失败降级全继承） | 原样 |
| 段2 | `claimBatchApply`（:916 原样——**这条翻 params，thumb 该 stale，用原方法正确**） | 原样 |
| 段3 | `BatchSidecarWriter` 串行队列 + clearDirty | 原样 |
| 部分应用 | `payload.filtered(by:)`（:128）+ 既有 partial dialog | 原样 |

- export preset：不进管线；面板读取 `exportRecipe` 填充 ExportState（D-11-CONTEXT-3 升级路径字面兑现）；`validate()`（ExportVariant:70）在 load 时跑，坏预设 typed 错误 + 降级（YiyinFontStore 自愈姿态）。
- 等价性测试：同一 instances 集走 preset-apply 与剪贴板-paste，终态 sidecar 字节 + 索引行全等。

### 5.3 存储/管理面

- `~/Library/Application Support/Lightamer/Presets/*.lightamer-preset`；PRES-02 导入/导出 = 文件拷贝（NSOpenPanel/SavePanel）零格式转换；CRUD = 文件系统原子写 + 扫描重扫自愈（YiyinFontStore 模式三分：会话注册/typed 错误/启动重扫）。
- LUT 不打包进预设（D-6）：lut iop params 存**库内名**引用（§6.6），预设跨机器可用前提 = LUT 库另行拷贝——文档化例外，不阻塞。

---

## §6 LUT（.cube iop，IOP-COLOR-08 = PRES-03 同批）

### 6.1 解析器规格（纯 Swift，typed throw）

- 识别键：`TITLE`（**含空格整行取值**存显示名——注意 dt 只跳过不取值，我们要取）、`LUT_3D_SIZE` / `LUT_1D_SIZE`（互斥）、`DOMAIN_MIN` / `DOMAIN_MAX`（1 float 广播三通道 **或** 3 floats，两形态都识别）、`LUT_1D_INPUT_RANGE`（2 floats，1D 域）、`#` 注释（含 CRLF `\r` 残留剥离——dt tokenizer `lut3d.c:701-751` 同款容错）、空行容忍、数据行 = 2-3 floats（1D）或 3 floats（3D）。
- 3D 数据序 = **red fastest**（文件顺序 r 内层；与 kernel 索引 `r + g*L + b*L²`（`lut3d.cl:45`）对齐——golden 解析用已知 2³ cube 断言角点位置锁序）。
- typed throw 枚举：`missingSize / conflictingSizes / sizeOutOfRange(>129 防御) / dataCountMismatch(expected:actual:) / nonNumericToken(line:) / domainInvalid(min>=max) / emptyFile / titleAfterData(容忍但记 warning)`。
- 与 dt 的差异（F4）：dt 拒 DOMAIN≠0..1；我们 remap 支持（裁决原文「DOMAIN_MIN/MAX 全识别」+ ROADMAP SC#4「honoring DOMAIN_MIN/MAX for float/HDR」）——**超出 dt 能力面，非移植缺口**。
- 真实世界脏数据形态：网络调研未做（标注留缝，1 次预算未用即收）；容错面以 dt 解析器实测行为为正本（注释/CRLF/TITLE/负号/科学计数法 `Double(String)` 原生支持）。**留缝项：多域名变体（Adobe `.cube` vs resin `.cube`）实测样本**——12-5 执行期遇到再补 fixture。

### 6.2 kernel 移植规格（tetrahedral）

- 正本 `lut3d.cl:29-60` verbatim 移植：`level-1` 缩放 → `convert_int` clamp → `rgbd` 分数部 → 八角点索引（`color = r + g*L + b*L²` × 3 float 步进）→ 三分数比较六分支四面体重心权值（P000/P100/P010/P110/P001/P101/P011/P111）。
- MSL 形态：`texture3d<float, access::read>`（**不用 sampler/不用 hardware filter**——`read(ushort3(p))` 手动取八角点，规避 float32 纹理不可 filter 的 Metal 限制，同时与 dt 的 CL buffer 语义等价）；管线像素恒 float32 RGBA（CONVENTIONS），kernel 中间量 float。
- 1D = 独立轻 kernel：per-channel 分段线性（`floor`/`frac` 两点插值），`texture1d<float>` R16Float；**执行期决策位**（CONTEXT specifics 预留）：若 `texture1d` filter/read 组合不称手，回退 `texture2d` 宽条（1×N）——两案都在 plan 里写死验收锚。

### 6.3 DOMAIN remap

kernel 内 uniform 参数化（避免 host 预缩放破坏 float32 域精度）：

```
v' = (clamp(v, domMin, domMax) - domMin) / (domMax - domMin) * (L - 1)
```

`DOMAIN` 默认 (0,1)；`LUT_1D_INPUT_RANGE` 同公式作用于 1D。remap 在 tetrahedral 索引数学之前。

### 6.4 精度论证：CLUT 纹理 rgba16Float 默认，rgba32Float 升格位保留

- half（rgba16Float）表表征误差 ~2⁻¹¹ 相对值；tetrahedral 输出权值和恒 1、凸组合不放大误差；下游 8/10-bit 输出量化步长 1/255~1/1024 **远大于** half 误差——视觉/字节双冗余。
- HDR 域：DOMAIN_MAX>1 时 CLUT 值可能 >1.0；half 上限 65504、2.0 附近步长 2⁻¹⁰≈0.001——覆盖 float32 管线 LUT 段需求（LUT 域转换后为 display 域量级）。
- 体积：33³ half = 143KB、65³ = 2.2MB、129³ = 17MB——内存预算无压力。
- **结论：默认 rgba16Float；golden 超差（tetrahedral vs float64 参考 CPU 双算阈值，plan 期定 ≤1/1024 绝对差）时升 rgba32Float**——`access::read` 手动插值下两格式 kernel 同源，升格零重写。

### 6.5 V50 槽位与模块骨架

- `V50Order.swift:126` `("lut3d", 36.0)` 已预留（源码核对 ✓）；36.0 < `terminalTailFloor` 70.0 = 层内 iop 合法；dt `iop_order.c:261` 同值 36.0（源码核对 ✓）。
- 骨架 = 既有 iop 文件对惯例：`LightamerCore/Sources/Pipe/IOP/Lut3d/Lut3dModule.swift`（params Codable：`lutName: String?`（库内名）+ `colorspace: LutColorspace`（默认 sRGB）+ `interpolation: .tetrahedral|.trilinear`）+ `Lut3dKernel.metal`；NeutralParams = lutName nil（未载入 = 恒等直通，管线零行为）。
- trilinear 插值作为枚举第二态（8 角点等权）——dt 同款枚举（`lut3d.c:1020`），成本 ~15 行 kernel，给 golden 对照用。

### 6.6 应用色彩空间选择器（INTEROP-2/3 防呆正主）

- 枚举：`sRGB / displayP3 / rec2020 / proPhotoLinear`（默认 **sRGB**）；dt `lut3d.c:1029-1031` 的 colorspace→profile 映射同构（源码核对：sRGB/Rec709/AdobeRGB/lin_proPhoto/lin_rec709/lin_rec2020 六态，我们收窄为四态 + 默认）。
- 应用序：working（linear Rec2020）→ 矩阵转换到 LUT 域 → tetrahedral 采样 → LUT 域 → 矩阵回 working。矩阵走 Phase 2 既有 colorin/colorout 系数资产（同源单实现，不新增 ICC 面）。
- 1D LUT 无域声明键时默认 sRGB gamma 面（.cube 1D 惯例）——文档化 + UI 提示。

### 6.7 导入库

- `~/Library/Application Support/Lightamer/LUTs/`；导入 = 拷贝 + 内容查重（FNV-1a 64 内容哈希，同哈希改名不重拷）；iop params 存库内**文件名**（相对），原始路径即弃——引用不腐烂（D-6 理由面）。
- 库缺失（preset 引用不存在的 lutName）= iop 降级恒等 + toast（unknown-op 同款姿态）。

---

## §7 测试策略（全 plan 验收底座）

| # | 面向 | 关键断言 |
|---|---|---|
| T1 | XMP golden 双向 | XMPWriter 输出字节 golden（fixture 含 rating/label/双 keywords 字段）+ `CreateFromXMPData` round-trip 值断言；JPEG APP1（marker `FFE1` + `http://ns.adobe.com/xap/1.0/\0` 段头 + packet 逐字节）与 PNG iTXt（keyword `XML:com.adobe.xmp`）、TIFF（tag 700 存在 + 值匹配）正向锚；HEIC/AVIF/WebP 产物 byte-scan 无 `x:xmpmeta`/`XML:com.adobe.xmp` 反向锚（11-02 同款防宿主漂移） |
| T2 | DB 迁移 | 手写 v1 fixture 库（25 列 DDL + 造行含边界值）→ open → 34 列/meta=2/旧行逐列字节不变/新列 NULL/二次打开幂等（列已存在跳过路径）/v99 REFUSE 保留/删库重建 parity 扩 v2 全列 |
| T3 | sidecar v3 | v2 文件降级读（五字段 nil）/ v3 被 reader 容忍路径（>current）/ **五字段写后 historyHash+paramsHash 逐字节不变** / sortedKeys 稳定 diff（v2→v3 升版只加键） |
| T4 | 关键字向量 | fixture 行集**精确**断言（L020）：四联式祖先命中集/子标签命中/`NatureHolics` 误伤对照组（裸 substring 命中而四联式不命中）/组合 AND/空值行排除/`|` 注入拒绝 |
| T5 | 谓词翻译层 | 每字段×操作符 → SQL 字符串 + binds 快照断言 + fixture 库精确行集；智能相册文件 round-trip |
| T6 | MetadataService | 万张 setRating：段1+段2 ≤5s（PERF-07 fixture 复用）+ `thumb_state`/`params_hash` 逐行不变 + 终态 dirty 全 0；crash 窗口注入（段3 前中断 → reopen → healDirtyRows 回旧值 + dirty=0）；批量加关键词/flag 全走同门 |
| T7 | preset 等价性 | preset apply == paste apply 终态 diff（sidecar 字节 + 索引行）；partial apply 子集语义；export preset load→面板填充 round-trip；坏预设 typed 降级 |
| T8 | LUT golden | 解析（1D/3D/DOMAIN 单值与三值/LUT_1D_INPUT_RANGE/CRLF/注释/八类 typed throw 表）；tetrahedral 已知点 vs CPU float64 参考实现（同 kernel 数学逐行双写）；dt 参考输出 golden-image（CONVENTIONS 纪律）；DOMAIN remap 已知点；色彩空间选择器矩阵往返已知点（色度恒等回环） |
| T9 | 回归 | 每任务全套 suite 绿（基线 1260/6skip/0fail）；`PRAGMA table_info` VERBATIM 断言更新 34 列（frozen-spelling 测试随迁移同批改） |

---

## §8 给 planner 的 Open Questions / 波次 / 风险

### 8.1 波次建议（验证 D-9：**成立，无需修正**）

5 plans / 4 waves；12-1（迁移+字段+服务+UI 接线）先行刚性不变；12-2∥12-3 并行成立（12-3 依赖 12-1 字段面，与 12-2 零交集）；12-4 预设依赖 12-1（PastePayload 同构面）；12-5 LUT 独立 GPU 腿收口+签核。12-1 建议内部任务序：sidecar v3 → DB v2 迁移 → MetadataService → EXIF 回填 → UI 接线（迁移先于服务，服务测试才能建在 v2 上）。

### 8.2 每任务验收草案（详测见 §7 映射）

- 12-1：T2+T3+T6 全绿 + grid overlay 手动走查（快捷键三态）+ 万张门数字入 perf.md。
- 12-2：T4+T5 + chips/QuickFilter/排序/智能相册 UI 走查（zh catalog 同批）。
- 12-3：T1 + 导出六格式×XMP 矩阵跑通 + 第三方 .xmp 导入对话框走查。**注入实现复杂度排序：JPEG APP1（append 级）< PNG iTXt（chunk append）< TIFF tag 700（IFD 重排——唯一中风险项，若超预算可裁 TIFF 为文档化例外延 13，SC#1 的「JPEG/TIFF/PNG 三格式内嵌」建议在 plan 期按实测工时裁决）**。
- 12-4：T7 + 管理器 CRUD/导入导出走查。
- 12-5：T8 + dt golden-image 对照 + 面板四件套 + 签核。

### 8.3 风险表

| 风险 | 级 | 对策 |
|---|---|---|
| TIFF XMP 注入（IFD offset 重排） | 中 | 见 8.2 裁决位；JPEG/PNG 两格式已保 SC#1 底线 |
| XMP packet >64KB（超长 keywords） | 低 | writer 上限保护 + typed 错误（执行期决策位已预留） |
| 用户存量库首跑迁移 | 低-中 | 幂等列检查 + fixture 级迁移测试（T2）；迁移失败 = 拒开并保留原库文件（不破坏性改写——ALTER 本身原位，WAL 先 checkpoint 由既有 pragma 面） |
| `EncodeIfPresent vs 恒写` 漂移 | 低 | plan 期定死一种 + golden 锁（§2.1） |
| EXIF 无值行反复重扫 | 低 | §2.5 哨兵/锚定策略 plan 期定 |
| 1D LUT texture1d 组合问题 | 低 | texture2d 宽条回退案已备（§6.2） |
| YiyinExportSettings 随 yiyin 面演进耦合进 preset | 低 | ExportRecipe 值类型已隔离（移交①）；演进 = schemaVersion additive |
| .cube 脏数据未知形态 | 低 | dt 容错面为底 + typed throw + 留缝 fixture（§6.1） |

### 8.4 网络调研留缝

- 真实世界 `.cube` 文件变体样本（多 DOMAIN 写法/畸形行）未做网络采集（本次预算收口在本地实证）；12-5 执行期以 dt 源码容错面 + 自造 fixture 先行，遇真文件异常再补。
- XMP 规范细节（IPTC Core 字段全表）未联网核对；v1 字段面（rating/label/subject/hier）已探针覆盖，IPTC 扩展属 defer 面（EXIF 编辑面板 v2）。

---

## §9 附：本 research 实测资产索引（全部即弃/不入库）

- XMP 探针 v4/v5：`/tmp/xmp_probe.swift`、`/tmp/xmp_probe5.swift`（已删；输出全文摘录于 §1.2）
- LIKE 计量：sqlite3 10k 行 ad-hoc（已删；数字录于 §3.4）

---

*Phase: 12-Metadata, Rating, Presets & LUT — Research*
*Researcher: ZCode subagent (gsd-phase-researcher), 2026-09-26*
