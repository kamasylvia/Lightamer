---
phase: 14
plan: "14-2"
title: "修图面（W2a，与 14-3 并行）：MCP-03 parity 初测（renderedPlane vs Export golden 同尺寸同参域）+ render_preview（上限 2048/30s 超时/typed error）+ apply_params（模块级 upsert + GUI-live 硬拒 imageLiveInEditor）+ load_image 无状态化（读面视图，planner 裁决 D5）+ list_iops（per-op 手写 schema 表 + CodingKeys 反射守卫）+ export_image（直渲 + ExportNamer + yiyin 缝）+ SC#3 修图端到端"
wave: 2
depends_on: ["14-1"]
autonomous: true
requirements: [MCP-01, MCP-03, MCP-09]
files_modified:
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift             # 新建：修图面 5 工具 handler 装配（load_image/apply_params/render_preview/list_iops/export_image）——纯 Swift，消费 Core 既有面 + registry 缝
  - App/Sources/Lightamer/MCP/Tools/IopCatalog.swift                 # 新建：per-op 手写 params 键集/类型/范围表（18 iop 面）+ 反射守卫测试支撑
  - Tests/LightamerTests/McpEditingToolsetTests.swift                # 新建：editing 域快照（5 工具）+ apply_params upsert/错误码全表/GUI-live 硬拒 + list_iops 反射守卫 + export 落盘边界
  - Tests/LightamerTests/McpRenderParityTests.swift                  # 新建：MCP-03 parity 初测（renderedPlane vs Export golden 同尺寸同参域逐像素/容差）+ render_preview 超时/上限断言
  - .work/gsd/phases/14-mcp-server/14-2-SUMMARY.md
  - .work/gsd/phases/14-mcp-server/14-2-DECISIONS.md
  - TODO.md                                                         # 14-2 勾选
  - LESSONS.md                                                      # 如踩坑
---

# Plan 14-2 — 修图面（W2a，与 14-3 并行）

> 背景：MCP-01/03 的主体（D-14-CONTEXT-7）。三个消费面全部已就位，本 plan 是接线不是算法：
> ① **render_preview ≈ 零新渲染代码**——`QuickLookRenderer.renderedPlane(imageURL:
> targetLongEdge:metal:registry:decodeLeg:)`（`QuickLookRenderer.swift:211-307`）就是
> 「ExportRenderer 减法孪生」参数化形态：disk sidecar → export chain（sRGB 终端 override）→
> routed pipe @ targetLongEdge（`$routesToExportQueue` L031 合规在源）→ fresh CIContextPool
> exit leg（R8/L014 fence 固化在源）→ `packedRGBA8`；MCP 腿 = renderedPlane → JPEG 编码 →
> base64。**不走 embedded-preview fallback**（QL 永不崩条款；MCP 要 typed error
> renderFailed/renderTimeout）；② **apply_params = SessionBatchApplier 三段同构直复**
> （PresetApplier.swift:105-117 先例）：disk truth compose + claim + 串行写——**不经
> SidecarStore 直写，无第三写路径**（研究项 A 结构性消解，§RQ-14-3④）；③ **parity 初测**
> （R6 消解位）：QL parity 模板（13-1）+ 11 期 Export golden 族基建现成。
> **planner 裁决（D5）**：`load_image` **无状态化**——apply_params 必带 relPath（server 侧
> 无会话级活动句柄），load_image 退化为读面工具（返回该图 sidecar 当前 instances/图层摘要
> 视图）。理由：RQ-14-14「两 client 轮流 load_image 上下文互踩」难题整段消解 + apply 即写
> 下无落盘时机问题 + 幂等重试安全（§RQ-14-5②）。
> 内部任务序刚性：T1（parity 初测先行——过了才划界成立，不过 = 停下报告划界重谈[CONTEXT
> 预案]）→ T2（apply_params）→ T3（list_iops）→ T4（export）→ T5（端到端）。

## read_first

1. `.work/gsd/phases/14-mcp-server/14-RESEARCH.md`——§RQ-14-4（**本 plan 正本**：renderedPlane
   形状正本/尺寸插位/parity 门域/30s 超时同源常数）、§RQ-14-5（apply_params 入参终表[模块级
   upsert]/**无状态化推荐**/GUI-live 拒写/错误码表）、§RQ-14-6（list_iops 返回面/手写表+
   反射守卫裁决）、§RQ-14-11（export_image 直渲终判/yiyin 参数位/Output 限域/ExportNamer/路径
   返回 note）、§RQ-14-8（render_preview 默认 1024/q85/**上限 2048**[D7 砍 4096]/预算表）、
   §RQ-14-3①④⑤（GUI-live 判据 PipeCoordinator.currentImageURL/三段汇合确认/render 读一致性
   「已保存编辑态」诚实条款）、§A 工具表 #1-4+19、§C 风险 R6
2. `.work/gsd/phases/14-mcp-server/14-CONTEXT.md`——D-14-CONTEXT-7（修图管线落位/MCP-03 口径
   = sRGB 编码域同像素/EDR 域不对齐诚实条款）、D-14-CONTEXT-5①②（元数据单源/params 写
   GUI-live typed error）、D-14-CONTEXT-4（base64 inline 单通道/上限表）+ 继承定案（L014
   fence/L009/失败语义永不静默降级）+ 验证红线（MCP-03 parity 专项/SC#3 字面）
3. `LightamerCore/Sources/Export/QuickLookRenderer.swift`：`renderedPlane`（:211-307——消费
   正本；`$routesToExportQueue` 路由/L014 fence/`boundedWait` :438-454/`renderTimeout` :69）、
   `image(from:)`（:311-314）、**embedded-preview fallback 段（:129-137）明确不走**
4. `LightamerCore/Sources/Export/ExportRenderer.swift`：headless 编排注释（:8-27）、
   `render(request:metal:registry:yiyinInjector:)`（:164-184——export_image 直渲正本）、
   encodeStage L009 原子晋升（:381-428，XMP mount :416-423 随 encodeStage 自动）、
   `ExportYiyinInjector` 生产缝（:46-65）、`ExportNamer.destinationURL` 消费点（:357-362）
5. `LightamerCore/Sources/Presets/PresetApplier.swift`：apply 三段（:105-117——apply_params
   同构直复模板；live targets skip 语义对照）、`LightamerCore/Sources/Session/
   SessionBatchApplier.swift`（disk truth compose/claim/串行写三段）、
   `LightamerCore/Sources/Session/MetadataService.swift:47`（单源汇合点确认——本 plan 不新增
   写路径的自证锚）
6. `App/Sources/Lightamer/State/PipeCoordinator.swift`：`currentImageURL`（:175）/`
   currentImageID`（:107）——GUI-live 判据精确来源（MainActor-hop 读，`LightamerApp.swift:49-52`
   assumeIsolated 先例）
7. `LightamerCore/Sources/Pipe/ModuleInstance.swift`：`(opName, multiPriority)` 寻址（:51-58）/
   `version` 字段（:66）+ Params Codable（`ParamsCoding` 既有编码域——反射守卫的 CodingKeys
   源）；11 期 Export golden 测试族（parity 基建；fixture 装配代码同源）
8. `LESSONS.md` L009/L014/L031 + `AGENTS.md` + `.work/GOAL-STATE.md`（Phase 14 续接点）+
   `.work/gsd/phases/14-mcp-server/14-1-SUMMARY.md`（若已落——registry 缝/错误码枚举/
   超时表/RenderGate 消费形态）

## 纪律（强制）

1. **提交纪律**：每任务独立提交（Conventional Commits，英文 message，只 add 本任务申报
   文件）；**不 push**。
2. **构建纪律**：`caffeinate -dis` 包裹一切构建（`xcodebuild build-for-testing` 先行）；
   **构建勿加 `-derivedDataPath`**；**新建文件后跑 `tuist generate`**（T1 提交前一次，
   后续每新建文件同）。
3. **测试纪律**：单测命令 = `Scripts/test-direct.sh '<Class>'`；判据 = Executed 计数行 +
   failures 行（Executed 0 = 判据失败）。**回归基线 = 1768/11skip/0fail**（14-1 收口后 =
   1768 + 14-1 新增，读 `.work/GOAL-STATE.md` 续接点取最新）；每任务全套 suite 绿，**0 fail
   目标**；在案 flake（`LayerE2E`/`ToneEqual` 负载型）隔离 ×3 归因单列入 SUMMARY，不计违约。
4. **边界纪律**：每任务边界检查 `.work/config.toml [gsd]`（`auto`/`paused`）。
5. **架构红线（本 plan 涉 Metal 面——L031 全款适用）**：①**L031 路由红线**：render_preview
   与 export_image 的 GPU 提交**只消费既有路由获取点**（renderedPlane 的
   `$routesToExportQueue` / ExportRenderer 既有 render 腿）——**禁止自建 command queue、
   禁止硬编 editor queue**；执行中发现需要新队列 = 停下报告，不得自建；②**L014 GPU 读回
   纪律**：像素读回只走 renderedPlane/ExportRenderer 既有 exit leg（fence 固化在源）——
   **禁止自写 `getBytes` 绕过 fence**；③GUI-live 判据 MainActor-hop 只读（assumeIsolated
   先例），禁止把 PipeCoordinator 引用出 App 层、禁止在 Core 触碰 GUI 状态；④**MCP 永禁
   直写 sidecar 文件字节**——apply_params 只走 SessionBatchApplier 三段；⑤L009：export
   落盘走 encodeStage 内建原子晋升，测试 fixture 禁 UNITEK 盘（真实 RAW 用仓内既有测试
   资产装配，11 期 golden 族同源）；⑥L013：跨进程身份 StableHash decimal String。
6. **执行期决策登记**：JSON→Params decode 错误定位格式、iop 手写表覆盖清单的取舍、
   render_preview format 参数域（JPEG 固定 vs 参数化）等入 `14-2-DECISIONS.md`，不臆造。

## Tasks

### T1 MCP-03 parity 初测 + render_preview（R6 消解位，首任务）

- **action**
  1. **parity 初测**（QL parity 模板 13-1 + 11 期 golden 族基建）：同 sidecar 同参下
     `renderedPlane` 输出 vs Export golden 族**同尺寸同参域成员**对照（targetLongEdge =
     golden 尺寸时逐像素/容差口径随 11 期先例）；fixture = 既有测试 RAW 资产 + 既有 golden
     装配（不入库，L009）。**不过 = 停下报告**（划界重谈 = CONTEXT 预案，不静默放行）。
  2. 新建 `EditingToolset.swift` 的 render_preview handler：`renderedPlane` →
     `image(from:)` → **JPEG 编码为 Data（ImageIO）→ base64** → MCP image content。
  3. 参数与上限（§RQ-14-8 预算表钉死，常量一处）：默认 longEdge **1024**/q**85**；上限
     longEdge **2048**/q**90**（**D7：4096 上限砍至 2048**——4096/q90 = 5.5MB base64/22K
     token 实测；超 2048 需走 export_image 落盘，工具描述写明）；入参 relPath 必带。
  4. 超时/错误（QL 同源常数）：`boundedWait` 形态 + `renderTimeout = 30s`（`McpTimeouts`
   表消费）——超时 = typed error `renderTimeout`，**不降级 embedded preview**；渲染失败 =
     `renderFailed`；notSessionMember/serverReadOnly 骨架错误照 §A 表。
  5. 渲染腿经 `McpRenderGate`（14-1 基建）串行。
  6. editing 域快照改：render_preview 注册 + 同 commit 改 `McpRegistrySnapshotTests`
     editing 段（工具面即安全面，原子变更）。
- **证据**：`McpRenderParityTests`——parity 对照数字在案（容差口径 + maxDiff）；超时/上限
  负例（longEdge 2049 → invalidParams；q 91 → invalidParams）；快照 editing 段含
  render_preview。

### T2 apply_params + load_image（无状态化裁决 D5 落地）

- **action**
  1. **load_image（读面工具）**：入参 relPath → 校验会话成员（rel_path 越界 =
     `notSessionMember`）→ 返回该图 sidecar 当前视图（instances 摘要[opName/multiPriority/
     enabled]/图层摘要/尺寸/orientation——§RQ-14-5② 读面形态；**不建立任何 server 侧活动
     句柄**）。工具描述写明无状态语义 + 「render_preview 反映已保存的编辑态」（2s debounce
     窗口诚实条款，§RQ-14-3⑤）。
  2. **apply_params（写面）**：入参 `{relPath, ops[]}`——每 op 按 `(opName, multiPriority)`
     寻址（`ModuleInstance.swift:51-58`；**id UUID 不暴露**）；语义 = **模块级 upsert**
     （同键替换 params / 不存在则新增 / `enabled` 可选翻转 / `"remove": true` 可选删实例；
     reset 单模块 = 该 op 带默认 params——三动词合一，不拆）；`params` JSON → 模块 Params
     Codable 直映（`ParamsCoding` 域）。
  3. **GUI-live 硬拒**：目标 relPath == `PipeCoordinator.currentImageURL`（MainActor-hop
     读）→ typed error `imageLiveInEditor`，错误文本带处置指引（「图像在 Lightamer 编辑器
     中打开；请让用户关闭后重试，或改用 GUI 操作」zh/en 双语键，L025 zh 标签）；未打开 →
     `SessionBatchApplier.apply` 三段（`PresetApplier.swift:105-117` 同构直复——**单图硬拒
     语义**，与 14-3 apply_preset 批量软跳[D8]不同，各自测试负例）。
  4. 错误码逐行：`unknownOp`（未知 opName）/ `invalidParams`（decode 失败，含 op 名+键名
     定位）/ `imageLiveInEditor` / `notSessionMember` / `serverReadOnly` / 超时 10s
     （`McpTimeouts`；批量上限 1000 时 60s——批量入参 additive 位 v1 不开则表值在案）。
  5. **golden 往返测试**：apply → 读盘 sidecar **字节面**断言（同参再 apply 幂等 = 字节
     不变；`recast-UUID` 规范化先例照 12-4 等价性测试）；upsert/新增/删除/enable 翻转四腿
     + GUI-live 负例 + serverReadOnly 负例。
  6. editing 域快照改：load_image/apply_params 注册（原子同 commit）。
- **证据**：`McpEditingToolsetTests`——upsert 四腿 golden 往返字节面 + GUI-live 硬拒 +
  错误码全表断言（每码一 case）；快照 editing 段 3 工具。

### T3 list_iops + per-op 手写 schema 表 + 反射守卫

- **action**
  1. 新建 `IopCatalog.swift`：**手写 per-op 轻表**（不做 Codable 反射生成——research §RQ-14-6
     裁决：反射产物「键全对、语义全无」）：每 iop 面 = `opName` / display 名 / `iopOrder`
     （v50 序）/ **`version`**（agent 缓存失效键）/ 适用域（raw/non-raw/both）/ params 键集
     与类型扁平表（type ∈ string|number|integer|boolean|enum:…|range:[min,max]）。
  2. **反射守卫测试**（反射只做守卫不做生成）：断言「手写表键集 == Params CodingKeys 反射
     键集」逐 op——该守卫同时 pin `version` 漂移（version 变 → 测试红 → 显式更新）。
  3. list_iops handler：遍历 ModuleRegistry + IopCatalog 合成返回（§RQ-14-6 返回面）；
    readOnlyHint 注解；无错误码面（骨架 internalError）。
  4. `apply_params` 与 list_iops 的配合契约写进两工具描述：apply_params 的 params 自由
    JSON + 服务端 decode 校验；list_iops 是 agent 获知参数键的运行时通道（MCP-01「iop 参数
    schema 元数据」字面）。
  5. editing 域快照改：list_iops 注册（原子同 commit）。
- **证据**：`McpEditingToolsetTests`——反射守卫全绿（18 iop 面逐 op 键集等值 + version
  pin）；list_iops 返回快照（结构形状断言）；快照 editing 段 4 工具。

### T4 export_image（直渲 + Output 限域 + yiyin 缝）

- **action**
  1. handler：`ExportRenderer.render(request:metal:registry:yiyinInjector:)`（:164-184）
     **全复用直渲，不入 ExportQueue**（§RQ-14-11①——队列语义对单图过重；并发控制 =
     `McpRenderGate` 共用）；渲染腿 L031/L014 红线同 T1。
  2. 输出位置：destinationDirectory **服务端钉死 `Session/Output/`**（入参不含路径）；命名
     = `ExportNamer.destinationURL`（`<stem>_<tag>` 派生 + `-1` 递增碰撞先例照抄）；
     encodeStage L009 原子晋升内建；XMP mount 腿随 encodeStage 自动（11 期 WebP 降级注记
     沿用，不新增工作）。
  3. 参数：variant 尺寸/格式/quality/colorSpace = ExportVariant 既有面直映（六格式 registry
     + ICC）；`yiyin` 默认 **false**，可选布尔（true = 注入 `ExportYiyinInjector` 生产缝，
     只透传「用当前 yiyin 面板配置」一个语义，不暴露边框细节参数——EXP-05 共享配置）。
  4. 返回 = **绝对路径文本 + `note` 字段**（明示「远程 client 无法直接读取本机路径；如需
     查看请用 render_preview 取 inline 预览或经 GUI/文件共享」——zh/en 键）；错误 =
     `exportFailed`/`serverReadOnly`/`notSessionMember`；超时 120s（`McpTimeouts`）。
  5. 测试：单图导出落 Output 域 + 命名派生/碰撞递增 + yiyin=false 无印框（字节面对照）
     + 越界路径拒绝负例（构造非 Output 目标 = 拒绝——服务端钉死语义自证）。
  6. editing 域快照改：export_image 注册（原子同 commit）——**editing 域 5 工具齐**。
- **证据**：`McpEditingToolsetTests`——导出落盘（L009 晋升 + XMP 在产物）+ 命名碰撞递增 +
  yiyin 开关两态 + 路径返回格式；快照 editing 段 5 工具。

### T5 修图面 SC#3 端到端

- **action**
  1. 端到端链（SC#3 字面）：载入 DSC00012.ARW（会话成员校验）→ `apply_params` ≥3 iop
     （exposure → 分属不同域的两个 iop → 第三 iop，具体组合以 11 期 golden 族 fixture
     为准）→ `render_preview` 取回 → 与本地渲染（Export golden 同参成员）**量化一致对照**
     （T1 同口径）。
  2. 走 InMemoryTransport（14-1 第三形态）跑全链自动化 + HTTP 形态复验（同一 handler 集，
     双宿主一致性红线）；「远程视角」断言 = 返回 base64 解码后与本地渲染 JPEG 字节/容差
     对照。
  3. 链路含一次 GUI-live 负例插步（图在编辑器打开 → apply_params 硬拒 → 关闭后重试成功）
     ——SC#3 + 拒写语义一体化断言。
- **证据**：`McpRenderParityTests` 端到端段（或并入 `McpEditingToolsetTests`，申报一处）
  ——全链绿 + 对照数字 + 双宿主一致。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 = 14-1 收口后最新 + 本 plan 新增，0 fail）；TODO.md
  14-2 勾选；`14-2-SUMMARY.md`（任务表/commit 表/parity 数字/证据）；`14-2-DECISIONS.md`
  （无状态化落地确认[D5]、上限 2048 落码确认[D7]、单图硬拒语义[D8 本 plan 半边]、其余
  执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| parity | MCP-03 初测数字在案（同尺寸同参域逐像素/容差） | `Scripts/test-direct.sh 'McpRenderParityTests'` |
| render_preview | 上限 2048/q90 + 30s 超时 typed error + RenderGate 串行 | `Scripts/test-direct.sh 'McpRenderParityTests'` |
| apply_params | upsert 四腿 golden 往返字节面 + GUI-live 硬拒 + 错误码全表 | `Scripts/test-direct.sh 'McpEditingToolsetTests'` |
| list_iops | 反射守卫逐 op 键集等值 + version pin | `Scripts/test-direct.sh 'McpEditingToolsetTests'` |
| export_image | Output 限域 + 命名递增 + yiyin 两态 + 路径返回 | `Scripts/test-direct.sh 'McpEditingToolsetTests'` |
| SC#3 端到端 | 载入 → ≥3 iop → 预览与本地量化一致（双宿主） | `Scripts/test-direct.sh 'McpEditingToolsetTests'`（端到端段） |
| 回归 | 全 suite 0 fail（基线 + 新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] MCP-03 parity 初测数字在案（renderedPlane vs Export golden 同尺寸同参域；不过 =
      停下报告划界重谈，R6 关闭）
- [ ] render_preview：默认 1024/q85 / 上限 2048/q90（D7）/ 30s 超时 renderTimeout 不降级
      / renderFailed typed / RenderGate 串行 / base64 image content
- [ ] apply_params：模块级 upsert（opName+multiPriority 寻址，id 不暴露）/ remove/enabled
      三动词合一 / SessionBatchApplier 三段直复零新写路径 / GUI-live 硬拒 imageLiveInEditor
      （双语处置指引）/ golden 往返字节面幂等
- [ ] load_image 无状态化（读面视图，无活动句柄——D5 planner 裁决落地）+ 诚实条款（已保存
      编辑态）进工具描述
- [ ] list_iops：手写 per-op 表（opName/version/iopOrder/适用域/键集类型）+ 反射守卫
      （键集等值 + version pin）
- [ ] export_image：直渲不入队列 / Output 服务端钉死 / ExportNamer 递增 / yiyin 默认 false
      生产缝 / 路径返回 + note / 120s 超时
- [ ] SC#3 端到端绿（载入 → ≥3 iop → 预览量化一致；双宿主一致；GUI-live 负例插步）
- [ ] editing 域快照 5 工具逐字（每任务原子演进）；全 suite 0 fail；每任务独立提交 + 边界
      查开关；不 push；SUMMARY + DECISIONS 落盘
