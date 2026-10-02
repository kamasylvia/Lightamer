# M2-9-01 SUMMARY — 数据模型与纯函数面（wave 1）

**Status:** COMPLETE（2026-10-02 夜间；执行 = ZCode subagent worker，`[gsd]`
`paused=false / auto=true` 全程未动）
**提交链:** `6835bd2`(T1 sizing 四模式) → `3a1ecb8`(边界外小修复，申报见
DECISIONS §8) → `e2a37f3`(T2 模板引擎) → `3b90709`(T3 三档+政策模型+载体) →
`ba379ac`(T4 命名预设 store)。**不 push。**
**对账底稿:** 同目录 `M2-9-01-DECISIONS.md`（KD-5 清单 / 域差异表 / shutter
对照 / 越界申报 / 机检记录）。

## 数字对账表

| 项 | 基线（M2-8-3 终态） | 本波终态 | Δ |
|---|---|---|---|
| Export bundle | 260/1/0 | **288/1/0**（191s，peakRSS 5901MB < 8G 门） | +28（6+11+11） |
| App bundle | 475/0/0（推算：481−本波 6） | **481/0/0**（185s，peakRSS 1311MB） | +6 |
| 全套推算 | 2577/16/0 | 2577 + 34 = **2611/16/0**（未跑全套——T5 门 = Export/App 两 bundle，其余五 bundle 零触碰零预期漂移） | +34 |

- **测试增量 34 vs front-matter 预估 45**（-11，偏差记录 DECISIONS §9）：新
  测试文件按「错误集/渲染锚合并进复合方法」组织，断言数远超方法数。
- 每任务边界 `[gsd]` 开关复查 = 全程 `paused=false / auto=true` 无变更。
- 定向轮逐次：T1 `YiyinExportSettingsTests 11/0/0`（6 新 + 5 既有保绿）+
  `ExportRecipeTests 22/0/0`；T2 `ExportFileNameTemplateTests 11/0/0`；T3
  `ExportCollisionPolicyTests 5/0/0` + `ExportMetadataPolicyTests 4/0/0` +
  `ExportRecipeTests 24/0/0` + `ExportNamerTests 16/0/0`（零 diff 全绿）；T4
  `ExportNamingTemplateStoreTests 6/0/0`（App bundle）。

## 任务逐条（commit × 验收）

| 任务 | commit | 交付 | AC 覆盖 |
|---|---|---|---|
| T1 | `6835bd2` | `OutputMode` + `bounds(w:h:)`/`physical(width:height:unit:dpi:)` + `ExportPhysicalUnit` + `allowUpscale`/`maximumEdgePixels` 字段 + 手写容错 decode + validate 四模式域 + `resolveExportResolution`（KD-1 三步数学 + DPI 宽度比修正）+ `targetSize` 委托改造；PanelView/derivedTag 编译性补臂 | AC1/2/3/9 |
| T2 | `e2a37f3` | `ExportFileNameTemplate`（parse/render/sanitizedStem/fallback 纯函数面 + typed 五错误 + `NamingTemplate` 模型） | AC4 |
| T3 | `3b90709` | `ExportCollisionPolicy` 三档（increment 默认逐字节）+ `ExportMetadataPolicy`（mode+6 bool，固定剥离三项）+ `ExportVariant` 三载体（drtOutput/metadataPolicy/embedICC + colorSpace 默认 .sRGB）+ 容错 decode + derivedTag 新臂向量 | AC5/6/2 |
| T4 | `ba379ac` | `NamingTemplateStore`（App 层，注入式 defaults，三内置不入库，CRUD + replacedName 语义 + 损坏降级） | AC7 |
| T5 | 本文 + DECISIONS | 双 bundle 全绿 + 双登记闭环 + 机检记录 | AC8/9 |

## 双登记闭环（AC8）

- `Project.swift`：`ExportFileNameTemplateTests` / `ExportCollisionPolicyTests`
  / `ExportMetadataPolicyTests` → `LightamerTestsExport`；
  `ExportNamingTemplateStoreTests` → `LightamerTestsApp`。
- `M2-4-0-BUNDLE-MAP.txt`：同批四行（EXPORT 11/5/4 + APP 6）+ M2-9-01 增行
  记录注。运行期总数基线上移至 2611（对账以各行 method 数为准）。
- 新 Core 源文件 2（模板引擎/政策模型）走 `LightamerCore/Sources/**` glob +
  `tuist generate`（新测试文件落盘后执行，L041 顺序纪律——期间踩到一次
  「先加错 bundle 再纠正」，纠正后重新 generate，终态登记以 Project.swift
  现文为准）。

## 偏差与发现（全部入 DECISIONS，逐条有据）

1. **边界外小修复**（`3a1ecb8`，front-matter 外文件）：T1 后 Export bundle
   首跑 1 fail（`QuickLookRendererTests` parity 腿 `functionNotFound
   ("compositeLayer")`）。三步归因（stash 干净树复现 → 全量重编不消 → 夹具
   考古）：**gitignored 活体夹具** `input/RAW/DSC00012.ARW.lra` 于 10-02
   00:52（基线跑后）被走查会话写入 1 层 + 37 instances，parity 腿自此进层
   复合驱动，而该测试从未注册 IOP metallib（潜伏缺陷：任何带层 sidecar 必
   炸）。修复 = 测试侧一行显式注册（全体 pipe 测试同款）；夹具保持原样。
   晨审可推翻（推翻 = revert 该 commit，fail 态回归，属既有环境问题非本波）。
2. **编译序强制**：plan 把 derivedTag/PanelView 补臂排在 T3，T1 加 case 即
   炸——补臂随 T1 落地、测试向量仍归 T3（DECISIONS §1 D8）。
3. **重载对替代默认参数**：destinationURL 三档若走默认参数 + throws 会强迫
   三个既有调用点（不在本 plan front-matter）加 try——以非 throwing 历史面 +
   throwing 全档面的重载对等价承载（DECISIONS §6 D6）。
4. **shutter Double→有理数推导**：Alcedo 直存 EXIF 有理数、我方上下文是
   Double 秒——推导层（<1s → `1-N`，≥1s → `N-1`，≤0 → 空）为本波自有，
   形态面与 Alcedo cpp:155-158 逐形态一致（DECISIONS §3）。
5. **date 实参白名单**：比 Alcedo 的未知字符直通更严（typed 拒绝），per plan
   错误集原文；`:` 因文件名非法被排除出分隔符集（DECISIONS §4）。
6. **源尺寸非正钳 1**（而非 Alcedo 的 typed 失败）：历史 targetSize 向量
   行为面保留；typed 失败正主 = physical DPI ≤ 0（D-M2-9-CONTEXT-6）（DECISIONS §2 D2）。
7. **tuist generate 顺序险情**：App 测试文件一度误挂 Export bundle（构建过、
   直启 `Executed 0`——L041 症状再现），纠正 bundle 归属后重新 generate 即
   消；教训与 L041 同族（登记行落在哪个 target 的 sources 清单里）。

## 交接（M2-9-02/03 消费缝）

- `resolveExportResolution`（含修正后 DPI）与 `ExportResolutionResult` ——
  03 T1 显式第 3 步切 renderStage sizing 腿 + `StageOutput.dpi = result.dpi`
  （checker E6）。
- `ExportVariant.drtOutput/metadataPolicy/embedICC` 载体 —— 02（DRT 渲染腿）
  / 03（元数据腿 + OMIT 后处理）消费；nil/default = legacy 字节冻结锚。
- `ExportCollisionPolicy` 三档 + 模板引擎 `resolvedStem` —— 03 命名腿接线
  （子文件夹、队列逐 job 求值）。
- `NamingTemplateStore` —— 04 检查器 Export 页的预设下拉 + 存/改名/删除。
- **未跑全套**：其余五 bundle（IOP/IOPParity/Layers/Library/Sessions）零源码
  触碰（QuickLookRendererTests 属 Export bundle），全套对账留给验收批或下一
  波收口（推算 2611/16/0）。
