# Phase 13: System Integration & Distribution - Context

**Gathered:** 2026-09-27
**Status:** Draft for planning — 10 项 OQ 全按推荐自动裁决〔晨审追认〕（D-13-CONTEXT-1..10，追认清单表见 decisions 末）

<domain>
## Phase Boundary

本 Phase 交付 macOS 系统集成（SYS-01..05）+ 色彩管理完备（COLOR-02/03）+ 发布管线（DIST-01..04），外加 2026-09-26 登记的蒙版命令面 UI 打磨批（ROADMAP §Phase 13 Notes :232）。11 项需求 + 1 个登记批。核心架构事实：

1. **两个 app 扩展进程是项目首例新 target 形态**——Quick Look appex 与 Spotlight importer 都是独立进程、独立签名单元、独立生命周期（ROADMAP Notes :232「separate processes with their own entitlements」）。它们**不依赖主 app 运行**：数据缝全部走磁盘资产（sidecar `.lra` / `session.lindex` / `thumbs/*.jpg`），渲染缝走 Core 级 headless 管线（`ExportRenderer.swift:1-56` 无 PipeCoordinator 依赖的先例就是本 Phase 的模板）。Tuist manifest（`Project.swift`）从 5 targets 扩到 7：新增 2 个 appex target，链接既有 LightamerCore/LightamerIOP framework（共享嵌入，不复制）。
2. **非沙盒决策延伸到扩展**——主 app 非沙盒（`ENABLE_USER_SELECTED_FILES` read-write，`Project.swift:135`）；QL/Spotlight 扩展要读**任意会话路径**（文件本体 + `.lightamer/` 隐藏目录 + `thumbs/`），沙盒扩展默认只有被请求文件本身的访问权、读不到兄弟隐藏目录——为保「扩展能完整消费会话资产」且与 ROADMAP Notes「decoupled … so the non-sandbox decision holds」一致，两 appex 同为非沙盒 + hardened runtime（分发配置），深度签名在公证前逐个嵌套 binary 执行（DIST-1 Notes 原文）。
3. **色彩完备 = D-COL3 预留位的兑现，不是新管线**——`ColorOutModule` 的 `Params.outputProfile`/`Params.intent`（`ColorOutModule.swift:54-56` D-COL3 reservation + `:101-109` Params 持久化位 + `:93-95` intent 注释「perceived/saturation/absoluteColorimetric Phase 13+」）与 `DisplayProfile` 头注释 `:31-32`（「Phase 13 (COLOR-03) adds manual profile selection + printer/soft-proof profiles」）都是 Phase 2 留好的插件点；**软打样语义是显示腿的 runtime override**（形状同 `displayProfileOverride` `:128` / `exportTargetOverride` socket `:76` 的 per-run data 先例），永不进 Params/history/export；COLOR-03 的 per-display 解析与 terminal-segment invalidation（`stableID` 折叠 `DisplayProfile.swift:104-123`）已就位，缺的只是「窗↔屏」追踪与手动覆盖面。
4. **视口从 near-static 升级为 zoom/pan/rotate 是 Phase 2 D-13 决策的首次翻转**——`EditorMTKView.swift:12` 注释「near-static blit (D-13: no zoom/pan)」与 `:318`（「fit/100% controls arrive with zoom/pan (Phase 2+)」）明示这是预留位；**最大回归面是 overlay 体系**：crop/liquify/retouch overlay host 与 eyedropper 全部假设 fit 布局（`ViewportFit.swift:7-16` 三消费者共享 `fittedRect`；06-06 遗留注记 overlay v1 坐标假设）——zoom/pan 的每一次视口变换都必须让 `ViewportFit` 的全部消费者同步感知，或按 D-13-CONTEXT-6 的互斥策略错峰。
5. **分发面 = 从 dev 自签证书到 Developer ID 的整机切换 + 项目首次公开**——`Project.swift:27-35` 注释钉死了本次切换（「Distribution switches to a real Developer ID in Phase 13 (DIST-02)」）；当前 remote = Azure DevOps 私有仓（无 LICENSE、无 `.github/`），DIST-01 GitHub 公开仓 = **新 remote**，发布前历史敏感审计是前置闸。签名凭据（Developer ID 证书）/ App Store Connect API key / repo 公开时机 = **人工阻塞项**（GOAL-STATE 阻塞节登记，13-4 执行前必须由用户供件）。
6. **Phase 12 移交清单五条的承接面**（`12-DISCUSSION-LOG.md:61-79`）——①DB v2 34 列（`SessionIndexSchema.swift:66-102`）= Spotlight importer 的抽取源，34 列 frozen-spelling 测试（SessionIndexStoreTests verbatim 断言）即 importer 的 schema 契约；②XMP 例外集复审位（HEIF/AVIF/WebP 不序列化 XMP packet）记为 Phase 14 同批复审项，本 Phase 的 QL/Spotlight 不依赖三格式 XMP（抽取源是 lindex/sidecar，不是文件内嵌 XMP）——分叉风险已登记（D-13-CONTEXT-3 理由节）；③Quick Filter/谓词翻译层与 ④`.lightamer-preset` 上游 = Phase 14 消费面，本 Phase 零触碰；⑤Manual-Only 13 行承接进 13-4 走查批，其中 **F-12-5-2（dt-GUI golden 人工对照）随 13-2 色彩批同轮做**（移交原文）。

**Phase 13 不做**：

- **沙盒 / Mac App Store**——PROJECT.md 约束锁定排除（非沙盒独立分发），本 Phase 的 appex 也非沙盒（Boundary 事实 2）
- **Sparkle 自动更新框架**——v2 面；v1 = DMG/zip 手动下载 + GitHub Releases
- **Spotlight 自定义 schema.xml / 自定义属性**——v1 只映射标准属性集（D-13-CONTEXT-3）；自定义属性需要随 app 安装 schema 并 `mdimport -X`，复杂度不成比例
- **Quick Look 内编辑/评分**——QL 只读预览；一切编辑动作进主 app
- **Metal 快路径软打样**——v1 软打样走 ColorSync/CG 精确腿（显示腿一次性变换，非热路径）；Metal ICC LUT 快路径视 research 探针结果再议（deferred）
- **蒙版算法扩展 IOP-MASK-06 Follow Edges / 07 Depth**——ROADMAP :319 已归 v2 节（可插队 v1 后期，非本 Phase 承诺）；本 Phase 只做蒙版**命令面 UI 装配**（内核语义 Phase 6 全在）
- **打印模块 / 地图视图 / 联机拍摄 / 跨 Session 全局搜索**——v2 表（TODO :302）既有排除项
- **Recipe 持久化 / WebP mux 元数据 / XMP IPTC Core 扩展字段**——11/12 既有遗留对表项（`12-DISCUSSION-LOG.md:81-95`），归属不变
</domain>

<decisions>
## Implementation Decisions

> 10 项 = discuss 起草识别的 OQ，全部按推荐项自动裁决〔晨审追认〕。晨间任一推翻 → 回注 planner 重开受影响面（推翻代价见追认清单表）。

### D-13-CONTEXT-1: Quick Look 扩展 = 单 appex target `LightamerQuickLook`（QLPreviewingController：thumbnail + full preview 双能力同 target）；非沙盒 + hardened runtime；appex 薄壳、逻辑下沉 Core
- **裁决**：①**单 appex 双能力**——macOS 现代 Quick Look 一个 appex 即可同时注册 `provideThumbnail(for:completionHandler:)`（缩略图）与 `preparePreviewOfFile(at:)`（全尺寸预览），拆双 target 无进程/签名收益；②target 结构 = Tuist `.appExtension`，bundleId `com.kamasylvia.lightamer.quicklook`（D-05 命名惯例延伸），链接 LightamerCore + LightamerIOP（framework 由宿主 app 嵌入、appex 经 `@rpath` 共享——分发时每个嵌套 binary 逐个 deep-sign，ROADMAP DIST-1 Notes）；③**非沙盒 + Release hardened runtime**（Boundary 事实 2——要读 `.lightamer/session.lindex` 与 `thumbs/` 兄弟资产，沙盒扩展拿不到）；④**appex 本体零业务逻辑**——文件定位/sidecar 解析/渲染全部是 Core 级可测函数（headless 渲染缝见 D-13-CONTEXT-2），appex 只做 QL 协议粘合；单测经既有直启宿主 suite 覆盖 Core 层，appex 不进 UITests（host 形态另案）。
- **理由**：单 target = 签名/公证/CI 矩阵的最小面（ROADMAP Notes 已警告扩展是独立签名单元——少一个就少一份 deep-sign 与 Gatekeeper 面）；QL 的两种请求天然同源（都要「当前编辑态的渲染图」），拆开只会复制数据缝；非沙盒与主 app 决策一致且是读隐藏目录的唯一简路。
- **Reversibility**: 拆双 target 是 manifest 加法；沙盒化 = 权限面重设计（高代价，见追认表）。

### D-13-CONTEXT-2: QL 渲染数据源与回退链 = sidecar 真身 → headless 管线（ExportRenderer 同缝、减 yiyin/导出 sizing）→ sRGB CGImage；缩略图请求先查双档资产；无 sidecar = 档 A 嵌入预览；渲染有界超时
- **裁决**：①**QL 预览语义 = 编辑器视口的离屏孪生**：文件 → 同目录 `<name>.lra` 读 history stack（磁盘文档即真相，`ExportRenderer.swift:7-13` 读取法）→ headless 管线渲染 → **显示终态**（colorout 目标 = sRGB，非导出目标、非 yiyin 印框——QL 展示的是「编辑到一半的照片」，与 Phase 9 双档缩略图的语义对齐，`09-CONTEXT.md:77`）；②**缩略图请求走三查**：a. `thumb_state` fresh 且 `thumbs/<pathhash>.jpg` 在（`ThumbnailPath`/`ThumbnailDiskStore.swift:75` read）→ 直读 JPEG 零渲染；b. stale/缺失 → headless 渲染 @ 请求尺寸（复用 `ThumbnailRenderRequest` 分辨率语义 `SessionThumbnailProvider.swift:63`）；c. 无 sidecar（pristine）→ **档 A 嵌入预览**（ImageIO，`09-CONTEXT.md:77` 双档定义）；③**全尺寸预览 = headless 渲染 @ QL 请求的 fit 尺寸**（不渲染 100MP 原生全幅——QL 窗口有限，PREVIEW bucket 分辨率语义已备）；④**渲染有界**：单次渲染超时（research 定阈值，秒级）→ 回退档 A，QL 永不无限等待；⑤新 Core 组件（暂名 `QuickLookRenderer`）= `ExportRenderer` 的减法孪生（无 yiyin injection、无 export sizing、无 quantize/encode——终点是 CGImage），复用 `ExportChainBuilder` 的 gamma/colorout 装配。
- **理由**：双档资产 + headless 缝全是已验证底座（Phase 9 缩略图 + Phase 11 导出渲染），QL 面只是**第三个消费端**；「预览=编辑态」是 SYS-01 黑体（「含调整后预览，不仅是原片缩略图」）；超时回退防的是 100MP 大图在 Finder 空格预览里卡死系统体验（QL 响应慢 = 用户感知 app 坏）。
- **Reversibility**: 回退阈值可调；`QuickLookRenderer` 若发现与 ExportRenderer 差异过小可合并参数化（实现期决策）。

### D-13-CONTEXT-3: Spotlight importer = 单 mdimporter target `LightamerSpotlight`；数据源 = 同会话 `.lightamer/session.lindex` 只读行读；属性映射 = 标准属性集（映射表 research 产）；自定义 schema 不做
- **裁决**：①数据链 = importer 收到文件 URL → 向上定位会话根（`.lightamer/session.lindex` 存在性探测）→ **只读**打开 lindex（schemaVersion 探测，>2 = 拒开降级零注册——`SessionIndexSchema.swift:49` 冻结契约）→ 按 rel-path 读行 → 映射 Spotlight 属性；②**映射表 = research 交付物**（RQ 项），推荐锚点：`rating` → `kMDItemStarRating`、`keywords` → `kMDItemKeywords`（`|` path 展平）、`color_label` → `kMDItemUserTags` 系、`camera_make/model`/`capture_date`/`iso`/`focal_length`/`aperture`/`exposure` → 各标准 EXIF 属性、`flag/note/layer_summary` → v1 **不映射**（无对应标准属性，自定义 schema defer）；③**自定义 schema.xml / 自定义属性不进 v1**；④importer 零写面：只读连接 + `synchronous=NORMAL` 语义天然安全，测试断言 lindex 文件 mtime/哈希零变。
- **理由**：SYS-02 验收词 =「评级/标签/关键字/EXIF 可被 Spotlight 检索」——标准属性集全数覆盖；34 列 DB v2 就是为此建的（移交①原文「importer 直接以该列集为抽取源」）；自定义属性要随 app 装 schema + 域重扫，成本/收益倒挂。
- **风险登记**：XMP 例外集复审位（移交②）——HEIF/AVIF/WebP 三格式若用户依赖**文件内嵌**元数据检索，本 Phase 的 lindex 抽取源天然覆盖（lindex 回填来自 sidecar/ImageIO，与宿主 XMP 序列化缺陷无关）；Phase 14 MCP 若需三格式内嵌元数据再复审（`12-DISCUSSION-LOG.md:63-65` 原文承接）。
- **Reversibility**: 属性映射表是纯数据可扩；自定义 schema additive（需 mdimport 重扫）。

### D-13-CONTEXT-4: 软打样（COLOR-02）= 显示腿 runtime override socket（形状同 `displayProfileOverride` 的 per-run data 先例，非 Params/history 项）；colorout 上游插 proof 变换段；引擎 = ColorSync/CG 精确腿；OOG = gamut check 开关（黑裁剪）
- **裁决**：①**软打样是「看」不是「改」**——proof 状态是 coordinator 级显示腿 override（per-run data，先例 = `ColorOutModule.swift:76` exportTargetOverride socket / `:128` displayProfileOverride），**永不进 history stack、永不进 export 链**（REQUIREMENTS :166 黑体「applied as the last transform before display — never baked into the edit」的字面执行）；②管线形状 = 工作空间 → **proof 段**（Rec2020 → 打印机 ICC，relative colorimetric + BPC）→ 既有显示变换（displayP3/sRGB fast path 或 ColorSync 腿）——proof 段插在 colorout 上游；③**引擎 = ColorSync/CG 精确腿优先**（ICC 变换是 ColorSync 本职；Metal 快路径 defer——proof 是显示腿旁路一次性变换，非拖动热路径），**research 头项探针 = CG 面软打样可达性**（CGColorConversionInfo 的 rendering intent 支持 + **BPC 可达性**——若 BPC 无公开开关，则黑点补偿在 proof 段内手做或降级注记，这是 COLOR-02 的头号技术不确定点）；④打印机 profile 来源 = ColorSync 已装档案列表（用户可选 + 最近记忆），**输出 profile 化不占 `Params.outputProfile` 导出枚举**（`ColorOutModule.swift:79-87` 的 adobeRGB/proPhoto/rec2020 是导出目标，语义不同不混用）；⑤**OOG 警告 = gamut check 开关**：开启时对 proof 段做往返 gamut 判定，超域像素以黑裁剪显示（dt `softproof`/gamut check 同语义）；UI 入口（视口工具条/快捷键）与警告形态（黑裁剪 vs 品红标记）planner 细化，默认黑裁剪。
- **理由**：D-COL3 预留位（`ColorOutModule.swift:54-56` + `:93-95` intent 持久化位）本来就为这批 profile/intent 准备；「显示腿 override 而非 Params」让 zero-risk 断言可写（proof OFF 逐字节直通，软打样对既有渲染管线零回归面）；BPC 探针先行是因为它是唯一可能改变管线形状（是否要手做黑点补偿 LUT）的未知数。
- **Reversibility**: proof 段是加法旁路；Metal 快路径可后补；UI 形态可调。

### D-13-CONTEXT-5: 多显示器 ICC（COLOR-03）= NSApplicationDidChangeScreenParametersNotification + window↔screen 追踪 → per-window `DisplayProfile.resolve` → 既有 terminal-segment invalidation 自动翻键；手动 per-display 覆盖 = Settings
- **裁决**：①**自动切 = 通知驱动的 re-resolve**：`NSApplicationDidChangeScreenParametersNotification`（屏幕拓扑/profile 变更统一信号）+ 窗口移动/跨屏事件 → 按**窗口所在屏**重跑 `DisplayProfile.resolve`（`DisplayProfile.swift:53-82` 四级匹配表原样）→ coordinator 重 commit colorout params → **既有缓存语义自动工作**（`stableID` 折叠进 piece.paramsHash，只有 terminal 段键翻转、上游平面存活——`DisplayProfile.swift:104-123` + `ColorOutModule.swift:58-61` SC#2 terminal variant，Phase 2 既有测试扩展即得）；②**手动覆盖 = Settings 面每显示器 profile 选择**（ColorSync 已装档案列表；`DisplayProfile.swift:31-32` 头注释预告的「manual profile selection」落位）——手动选择 = 把该屏解析结果替换为指定 ICC（走 `.colorSyncFallback` 精确腿，**顺带兑现 fallback 腿的 exact-TRC 工作**：`DisplayProfile.swift:136-151` 注释的「sRGB workalike」文档化近似在手动指定精确 ICC 后消除）；③多窗口每窗独立 profile（窗 A 在 P3 内建屏、窗 B 在外接屏）= per-window 解析的自然结果，D-COL2 的 window-screen 注入语义（`DisplayProfile.swift:84-88` `current()` 的 coordinator 注入注释）延伸到双窗。
- **理由**：解析/翻键/缓存三层全是已交付底座（02-04-03），缺的只是「何时重解析」的事件面——通知 + 追踪是 AppKit 标准形态；手动覆盖顺带还了 fallback 腿 exact-TRC 的文档债，一石二鸟。
- **Reversibility**: 手动覆盖 UI 可增删；通知面是常量接线。

### D-13-CONTEXT-6: 手势（SYS-03）= AppKit NSGestureRecognizer 面（magnify/rotate/pan + scrollWheel 双指平移）挂 MTKView bridge；zoom 状态机 = fit/100%/自由（光标中心）；ViewportFit 单点扩展；overlay 互斥 = crop/liquify/retouch 激活时 zoom 锁 fit
- **裁决**：①**选 AppKit 不选 SwiftUI 手势**——macOS 触控板捏合/旋转的原生事件流是 NSView 的 `magnify(with:)`/`rotate(with:)` + 滚轮双指平移 `scrollWheel`（连续 delta、光标锚点、与 NSResponder 链天然集成）；SwiftUI `.magnification/.rotation` 在 macOS 上对手势细节（锚点/结束态/滚轮平移）表达力不足；挂点 = `EditorMTKView` 的 NSViewRepresentable bridge（NSGestureRecognizer 或 NSView 子类覆写，实现期定）；②**zoom 状态机 = fit（默认）/ 100% 像素 / 自由缩放**（光标中心锚定），pan = 滚轮双指/拖拽；blit 腿扩展 = `aspectFitUniforms`（`EditorMTKView.swift:318` 注释预留位）加 zoom/pan 偏移向量，`ViewportFit.fittedRect`（`ViewportFit.swift:33`）单点数学扩为 `viewportTransform` 供全部消费者取用——**禁止第二份 fit/zoom 数学**（三消费者共享单点是该文件的本职，`ViewportFit.swift:7-16`）；③**overlay 互斥策略（v1 从简）**：crop/liquify/retouch 激活时 zoom/pan 禁用锁 fit（这些 overlay host 的坐标假设是 fit 布局，`ViewportFit.swift` 三消费者注释 + 06-06 遗留「overlay v1 坐标假设」）——切面板 = 自动回 fit；mask brush/stamp 不在禁用集：绘制坐标经 `viewportTransform` 逆映射（mask overlay 已走 ViewportFit 取 uv，同步升级映射函数即可）；④ eyedropper/crop overlay 的 uv 取样同步走新 transform（同一函数，零特判）。
- **理由**：SYS-03 验收词逐项（双指缩放、捏拉、旋转、双指拖动平移）在 AppKit 面是原生事件一对一；互斥策略把「overlay 全量 zoom 化」这个高回归风险面从 v1 摘出——先交付视口 zoom 本体 + mask 绘制可用，crop-while-zoomed 是 v2 顺位（deferred）。
- **Reversibility**: 互斥集是配置表可扩；viewportTransform 函数签名稳定后 overlay zoom 化是逐 host 增量。

### D-13-CONTEXT-7: 拖放导入（SYS-04）= 默认复制入 `Capture/`（Move = Option 修饰键）；双落点（会话网格 + 编辑器区）；路由复用既有 openSession/文件打开编排
- **裁决**：①落点语义：拖入**已开会话的网格/窗口** → 默认**复制**文件入该会话 `Capture/`（Session 哲学：文件随会话走；Option+拖 = 移动），批量多文件支持 + 进度/取消（大文件 USB 卷场景，L009 环境自警）；拖入**编辑器区** = 打开该图直接编辑（单图无会话路径——既有单图加载流 `EditorState.load` 原样，sidecar 随图落原图旁）；拖入**空态/无会话** = 走既有「文件夹→会话」打开（`EmptyStateView.swift:57` onDrop fileURL 先例扩文件级）；②路由复用：导入完成后索引入网格 = `openSession` 编排的既有 reconcile（新文件出现 → 扫描器 diff 收编——导入走显式管线写文件，FSEvents hint 或显式 refresh 任一可触发，不依赖事件时序）；③安全语义：同盘/跨盘统一 `FileManager.copyItem` + 失败逐文件报错不中断批；**源文件零改动**（复制默认下 golden：源目录 mtime/内容不变）。
- **理由**：默认复制与 C1 捕获语义一致（拖入 = 供给会话）且可逆（删除副本即回原状）；Move 设修饰键是把不可逆动作藏到显式意图后面；双落点 = SYS-04 黑体「Finder → session 或 editor」字面。
- **Reversibility**: 修饰键语义/落点集可扩（如 Output/ 直投导出区——deferred）。

### D-13-CONTEXT-8: 分发链（DIST-01..04）= MIT + GitHub 新公开仓（全历史推送 + 前置敏感审计）+ Developer ID 切换 + notarytool（warnings=errors）+ DMG/zip 双载体 + GitHub Actions macOS runner tag 流水；凭据/账号 = 人工阻塞项登记
- **裁决**：①**license = MIT**（ROADMAP SC#4「MIT or similar」取最简）；②**GitHub 仓 = 新 remote 全历史推送**（开源完整性——历史即工程过程记录；发布前前置闸 = **敏感审计**：全历史扫描凭证/token/内部域名/绝对路径，命中即清洗或改 squash 起点——二选一是用户裁决位，默认全历史）；③**签名切换**（`Project.swift:33` 注释预告）：Release 配置 `CODE_SIGN_IDENTITY` → Developer ID Application，Debug 保 dev 自签（L011 三件套不动——测试授权依赖稳定证书）；**hardened runtime Release 已开**（`Project.swift:48`）；④**公证 = notarytool**（App Store Connect API key 认证），**notarization log 任何 warning 按 error 处置**（ROADMAP Notes「Gatekeeper enforces what notarization only warns」字面）；staple 后置；⑤**载体 = DMG（`hdiutil` UDZO）+ zip 双产物**——create-dmg 美化卷面 deferred；`Bundle.main` 资源路径纪律（DIST-2 Notes）随批走查；⑥**CI = GitHub Actions macOS runner**：PR/push 跑构建+测试（无签名 build），tag 触发完整链（构建→测试→签名→公证→DMG/zip→GitHub Release）；凭据 = AC API key 存 GitHub Secrets；⑦**人工阻塞项**（GOAL-STATE 登记待供件）：Developer ID 证书 + 私钥、AC API key、GitHub 仓创建/公开时机、Secrets 配置——13-4 执行前必须就位；GUI-20（dev-signed 层 B 资产供给）的 Developer ID 复验挂 13-4 验收轮（TODO :296 登记）。
- **理由**：全历史 = 开源项目的可审计性默认；DMG+zip 双载体覆盖「拖安装」与「解压即用」两类用户；CI 无签名日常构建把签名面收敛到发布 tag 一处，runner 上无证书也不绿不了 PR。
- **Reversibility**: license 变更 = 文件替换；squash 起点改选 = 发布前一次性决策；DMG 美化 additive。

### D-13-CONTEXT-9: 蒙版命令面 UI 批（2026-09-26 登记）= 13-3 UI 批内装配；三件套 + LayerStack 命令路由；内核零改；GUI-19 同批
- **裁决**：①**落位 = 13-3 交互与 UI 批**（与手势/拖放同 plan 的 UI 装配主题）；②命令清单逐项对标（ROADMAP :232 登记）：`Duplicate` / `Duplicate-and-Invert`（= duplicated + inverted 位翻转）/ `Fill`（= `MaskCombiner.fill` 常数平面语义，`MaskCombiner.swift:266`）/ `Clear`（归零 mask 记录）/ `Reset Edits`（该蒙版实例参数回默认）——菜单命令挂在蒙版列表上下文菜单 + 快捷键；③**overlay 三态切换** = On-Black / Rubylith / 半透明（`MaskToolbarView.swift` 334 行的显示选项扩展；三态是**显示样式**枚举，不改蒙版数据）；④**蒙版列表 enable 勾选** = `AdjustmentLayer.enabled`（`AdjustmentLayer.swift:43`）已有字段的 UI 暴露（列表行 checkbox），勾选切换走既有 history commit 语义；⑤**内核零改**：`AdjustmentLayer.duplicated()`（`:81` 新 UUID 克隆语义）、`MaskCombiner` 的 `inverted` 位（`:47`）与 combine 装配全部 Phase 6 已验——本批纯 App 层 UI 装配 + 命令路由（`LayerStack` 既有编辑入口），**新命令每步过 history（⌘Z 可退）**；⑥**GUI-19（层链行不显示，中）同批修复**（TODO :296 UI 打磨轮登记位正主）；GUI-20 不在本批（挂 13-4 Developer ID 复验）。
- **理由**：登记原文「内核语义 Phase 6 全在……缺 UI 装配；对标 Nitro Photo，UI 级非算法缺口」——落位判据就是这条；与手势/拖放同 plan 是因为三者的验收形态同构（GUI 装配 + Manual-Only 走查）。
- **Reversibility**: 命令入口/快捷键表可调；overlay 三态枚举 additive。

### D-13-CONTEXT-10: 波次分解建议 = 4 plans / 3 waves（13-1 系统扩展底座先行；13-2∥13-3 可选并行经 planner 裁决；13-4 分发收口+Manual-Only 承接+签核）
- **裁决**（给 planner 的依赖序基线）：**13-1**（系统扩展底座：Tuist 双 appex target + `QuickLookRenderer` Core 缝 + QL thumbnail/preview 接线 + Spotlight importer + 34 列契约同批 + **QL 渲染时延探针**）→ **13-2**（色彩完备：软打样 proof 段 + gamut check + 多显示器追踪/手动覆盖 + **BPC 可达性探针先行** + F-12-5-2 dt-GUI 对照同轮）∥ **13-3**（交互与 UI 批：手势 zoom/pan/rotate + 拖放导入 + 蒙版命令面批 + GUI-19 + SYS-05 本地化收口审计）——13-2/13-3 Core 面正交（色彩管线 vs 视口/导入/UI），UI 载体耦合点少，planner 裁决并行度 → **13-4**（分发收口：敏感审计闸 + Developer ID/公证 + DMG/zip + CI + GUI-20 复验 + Manual-Only 13 行承接走查 + 签核）。
- **理由**：13-1 是全 Phase 唯一的新进程/target 形态（结构风险最高、探针最早该跑）；色彩批带研究探针（BPC）自成一体验证闭环；交互批全是 App 层 UI 装配（风险低可并行）；分发收口必须最后（审计闸 + 凭据人工项 + 全 Phase Manual-Only 走查一次清）。
- **Reversibility**: plan 边界可并/拆；刚性 = 13-1 先行（target 结构是其余面的宿主）、13-4 收口含签核。

### 继承定案（非 OQ，上游已论证、下游不得重开）

- **真身恒 sidecar / 索引可重建**——QL/Spotlight 一切读面只读；lindex 打开带 schemaVersion 探测（>2 拒开降级）；「mutable and untrusted」纪律跨进程延续。
- **34 列冻结契约 = Spotlight 抽取源**（移交①，`SessionIndexSchema.swift:66-102`）——importer 读面改动须同批过 frozen-spelling 测试（SessionIndexStoreTests verbatim 断言）。
- **L013 哈希纪律 / one-way 格式锁**——一切跨进程身份禁 Swift `Hasher`；sidecar/lindex 读写不复发明。
- **非沙盒 + Release hardened runtime + Manual signing 切换 Developer ID**（`Project.swift:27-48` 注释原文）；Debug 测试授权三件套（L011）不动。
- **SYS-05 本地化 = 收口审计非新框架**——String Catalog 结构已在（`Resources/Localizable.xcstrings`，zh/en 双语 1000+ 键），L025 zh 标签纪律延续；本 Phase 新 UI（zoom HUD/proof 面板/蒙版命令/设置页）每键 zh 同批（L025 smoke 数字随 suite 报），系统语言跟随是 xcstrings 本职零代码。
- **GPU 读回 L014 / 单窗口 L012 / CI 纹理 L029 定向纪律 / overlay 验收 L021 观察层量化**——QL 渲染、多窗色彩、手势后的 overlay 走查全适用。
- **单测直启宿主**（L019b `Scripts/test-direct.sh`）——新 Core 面全走既有 suite；`xcodebuild test` 保留给 UITests/xcresult 需求。
- **执行纪律**——`.work/config.toml [gsd]`（auto/paused）每任务边界与派发前必读；C 档门控三点停（research 定稿后停 / 每 plan 闭环停 / 签核前停）。

### 验证红线（全 plan 写死，执行期不得放宽）

- **QL parity 专项**：同 sidecar 同参数下，QL 全尺寸预览 vs 编辑器视口**内容级一致**（程序化差分，容差 plan 定）；无 sidecar → 档 A 回退 golden；stale → 渲染回退链逐级断言；**渲染超时回退**有界性测试（假慢渲染注入）；QL 缩略图 fresh 直读路径零渲染断言（计数探针）。
- **Spotlight 只读 + 契约专项**：importer 全流程 lindex 文件 mtime/哈希零变断言；34 列 frozen-spelling 同批；属性映射表逐项单元测试（行值 → 预期属性值）；无 lindex / schema 超 v2 → 零崩溃零注册降级。
- **软打样零回归专项**：proof OFF = 显示腿逐字节直通（既有渲染 golden 矩阵全绿）；proof ON 不改 history/不进 export（导出 golden 逐位不变断言）；OOG 判定 golden（已知超 printer 域样本集）；BPC 探针结论落档后才许写 proof 段实现。
- **多显示器**：profile 切换 → 仅 terminal 段键翻转、上游平面存活断言（SC#2 terminal variant 测试扩展）；双窗双 profile 独立性；手动覆盖后 fallback 腿 exact-TRC（ICC 字节 identity 断言）。
- **手势/overlay 安全**：overlay 互斥矩阵断言（crop/liquify/retouch 激活时 zoom 输入被吞且自动回 fit）；zoom 后 mask stamp 命中精度门（光标点 vs 落点 <1px）；blit zoom/pan uniforms 正确性 pattern 测试（L021 常驻回归扩展）；eyedropper uv 经 transform 后取样正确。
- **拖放**：复制语义源文件零改动 golden；批量失败单列不中断；Move 语义显式意图（无修饰键绝不搬移）。
- **分发链**：`codesign -v` 级联校验清单（app + 每 framework + 每 appex 深签）；notarization log 零 warning（warning=error 处置记录）；**quarantine 实测**：下载产物带 `com.apple.quarantine` xattr 首启 Gatekeeper 放行（spctl + 真机走查）；CI 零凭据泄漏扫描（secrets 不入日志/产物）。
- **敏感审计闸**：git 全历史凭证扫描报告落档（13-4 第一任务），命中处置后才许公开仓操作。
- **防空转/L014/L010/L020/L025/面板纪律**：同 09/12/16-CONTEXT 全套；新面板/菜单 zh 键同步（L025 smoke 数字随 suite 报）。
- **回归纪律**：每任务全套 suite 绿（现基线 **1553/9skip/0fail**，16-4 收口后）；每任务边界查 `.work/config.toml [gsd]`。

### Open Questions 晨审追认清单（10 项全按推荐自动裁决）

| OQ | 裁决一句 | 关键理由 | 推翻代价 | Reversibility |
|---|---|---|---|---|
| 1 QL 形态 | 单 appex 双能力；非沙盒+hardened；薄壳+逻辑下沉 Core | 签名/CI 矩阵最小面；数据缝天然同源 | 拆双 target = 签名公证面翻倍；沙盒化 = 权限面重设计（读不到 `.lightamer/`） | 拆分是 manifest 加法 |
| 2 QL 数据源 | 三查回退链（thumbs 直读→headless 渲染→档 A）；预览=编辑态 sRGB CGImage；超时回退 | 双档+headless 缝全是已验证底座；QL 慢=系统级体验事故 | 全幅原生渲染 = 100MP 每空格一次风暴；无回退链 = pristine 图预览缺失 | 阈值/回退链可调 |
| 3 Spotlight | 标准属性集；lindex 只读行读；自定义 schema defer | SYS-02 验收词全数覆盖；34 列就是抽取源（移交①） | 自定义 schema = 装 schema+域重扫，成本倒挂 | 映射表纯数据可扩 |
| 4 软打样 | 显示腿 override 非 Params；colorout 上游 proof 段；ColorSync 腿；OOG 黑裁剪；BPC 探针先行 | 「never baked」黑体的字面执行；proof OFF 逐字节直通零回归 | proof 进 Params = 管线/导出/历史三面回归 | Metal 快路径可后补 |
| 5 多显示器 | 通知+window 追踪→既有 re-resolve/翻键；手动覆盖进 Settings（顺带还 exact-TRC 债） | 三层全是 02-04 已交付底座，缺的只是事件面 | 自建第二解析/缓存面 = 重复 D-COL2/3 | 覆盖 UI 可增删 |
| 6 手势 | AppKit recognizer 面；fit/100%/自由+光标中心；ViewportFit 单点扩展；crop/liquify/retouch 激活锁 fit | macOS 原生事件流一对一；互斥把 overlay zoom 化摘出 v1 | SwiftUI 手势 = 锚点/滚轮表达力不足；overlay 全量 zoom 化 = 最高回归面 | 互斥集配置表可扩 |
| 7 拖放 | 默认复制入 Capture/（Option=Move）；网格+编辑器双落点；复用 openSession 路由 | C1 捕获语义；复制可逆、Move 藏显式意图 | 默认 Move = 不可逆动作成默认 | 修饰键/落点集可扩 |
| 8 分发 | MIT；GitHub 新仓全历史+敏感审计前置；Developer ID 切换；notarytool warnings=errors；DMG+zip；CI tag 流水；凭据=人工项 | 开源完整性默认；签名面收敛到发布 tag | squash 起点 = 丢工程史（可改选）；凭据缺位 = 13-4 全阻塞 | license/美化 additive |
| 9 蒙版命令面 | 13-3 UI 批装配；内核零改；enable 勾选=既有字段暴露；GUI-19 同批；GUI-20 挂 13-4 | 登记原文「缺 UI 装配」判据；验收形态与交互批同构 | 内核重写 = 推翻 Phase 6 已验面 | 命令/快捷键表可调 |
| 10 波次 | 13-1 扩展底座先行 → 13-2（色彩+BPC 探针）∥13-3（交互+UI 批）→ 13-4 收口 | 13-1 是 target 结构风险根、探针最早；分发收口必须末位 | 串行拉长日历；13-4 提前 = 审计闸/凭据前置空转 | plan 边界可调 |

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.work/gsd/ROADMAP.md` §Phase 13（:209-232——Goal/SC#1-4/Notes：扩展独立 entitlements / deep-sign / notarytool warnings=errors / Bundle.main 纪律 + :232 蒙版命令面批登记 + :319 蒙版算法扩展 v2 节）；`.work/gsd/REQUIREMENTS.md` SYS-01..05（:212-216）/ DIST-01..04（:220-223）/ COLOR-02/03（:166-167）
- `.work/gsd/phases/12-metadata-presets-lut/12-DISCUSSION-LOG.md:48-101`（签核终节：**Phase 13 移交清单五条 :61-79** + 遗留对表 10 行 + Manual-Only 13 行承接）
- `.work/gsd/phases/09-session-management/09-CONTEXT.md`（:41-42 D-09-CONTEXT-2 `.lightamer/` 派生缓存落位 / :77 双档缩略图管线硬约束 / :82 会话切换 teardown 五步——QL 进程与主 app 并存时的资产一致性语境）
- `Project.swift`（:27-35 Manual signing 注释 + Developer ID 切换预告 / :45-48 per-config hardened runtime / app target infoPlist CFBundleDocumentTypes / 5 targets 现状——7 targets 扩展点）
- `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift`（:54-56 D-COL3 reservation / :79-87 OutputProfile 枚举 / :90-95 RenderingIntent / :101-109 Params / :76 exportTargetOverride socket / :128 displayProfileOverride——软打样 override 形状正本）；`LightamerCore/Sources/Foundation/DisplayProfile.swift`（:31-32 Phase 13 预告 / :53-82 resolve 四级匹配 / :104-123 stableID / :136-151 linearCGColorSpace workalike 注释）
- `LightamerCore/Sources/Session/SessionIndexSchema.swift`（:49 schemaVersion=2 / :66-102 34 列冻结表）；`ExportRenderer.swift`（:1-56 headless 流程注释——QuickLookRenderer 的减法孪生模板）；`SessionThumbnailProvider.swift`（:63 ThumbnailRenderRequest / :112 actor）；`ThumbnailDiskStore.swift`（:75 read）
- `App/Sources/Lightamer/UI/EditorMTKView.swift`（:12 near-static D-13 注释 / :318 fit/100% 预留）；`App/Sources/Lightamer/UI/Overlay/ViewportFit.swift`（:7-16 三消费者单点声明 / :33 fittedRect）；`App/Sources/Lightamer/UI/EditorAreaView.swift`（:227 SpatialTapGesture 既有手势锚）；`App/Sources/Lightamer/UI/EmptyStateView.swift`（:57 onDrop fileURL 先例）
- `LightamerCore/Sources/Layers/AdjustmentLayer.swift`（:43 enabled / :76-81 duplicated 新 UUID 语义）；`LightamerCore/Sources/Layers/Masks/MaskCombiner.swift`（:47 inverted 位 / :266 fill）；`App/Sources/Lightamer/UI/Inspector/LayersPanelView.swift`（673 行——蒙版列表/勾选挂点）+ `App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift`（334 行——overlay 三态挂点）+ `App/Sources/Lightamer/State/LayerEditingState.swift`（命令路由状态面）
- `TODO.md`（:296 蒙版命令面→Phase 13 + GUI-19/20 登记 / :302 v2 排除表）；`.work/GOAL-STATE.md`（:80 下一程 = Phase 13 开环——人工阻塞项登记节）
- `AGENTS.md`（Phase 执行模型 + 暂停机制 + Conventions）+ `LESSONS.md` L009/L011/L012/L014/L017/L019b/L020/L021/L025/L029/L032
- `.work/config.toml [gsd]`（auto/paused 开关——每任务边界必读）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **headless 渲染缝**：`ExportRenderer`（sidecar→ExportChainBuilder→materialize→render→CGImage 全链无 PipeCoordinator）——QL 渲染的减法孪生模板；`ExportChainBuilder` 的 gamma/colorout 装配直接复用（QL 目标 = sRGB display 终态）。
- **双档缩略图资产**：`thumb_state` 三态判定 + `thumbs/<pathhash>.jpg`（`ThumbnailDiskStore`）+ `ThumbnailMemoryCache`——QL 缩略图快路的现成数据源；`ThumbnailPath` 定位函数进程无关。
- **Spotlight 抽取源**：34 列冻结表 + `SessionIndexStore` 只读打开形态（actor 单连接；importer 侧用一次性只读连接即可，无并发面）。
- **色彩三层**：`DisplayProfile.resolve`（四级匹配）→ coordinator 注入 → `stableID` terminal-segment 翻键——COLOR-03 只补事件面；`exportTargetOverride`/`displayProfileOverride` 双 socket 先例——COLOR-02 proof override 的形状正本。
- **视口数学**：`ViewportFit.fittedRect` 三消费者共享单点——zoom/pan transform 的扩展基座；`aspectFitUniforms` 预留注释是 blit 腿扩展位。
- **蒙版内核语义**：`duplicated()`/`enabled`/`inverted` 位/`fill` 常数平面/combine 装配全已验——命令面纯 UI 装配。
- **拖放先例**：`EmptyStateView.swift:57` onDrop fileURL + `LayersPanelView` 层拖拽（NSItemProvider/onDrop 对）——文件拖放与修饰键语义的实现参照。
- **UI 载体**：`SettingsView.swift`（软打样/多显示器手动覆盖/Spotlight 帮助面挂点）、`StatusBar.swift`/视口工具条（proof toggle/zoom HUD 候选位）、`InspectorView` 面板体系（蒙版命令入口）。

### Integration Points

| 底座面（Phase 2/6/9/11/12） | Phase 13 落位 |
|---|---|
| 34 列 DB v2 + schemaVersion 冻结（12-1） | D-13-CONTEXT-3：Spotlight 抽取源 + 只读契约 |
| 双档缩略图（9-3）+ headless ExportRenderer（11-03） | D-13-CONTEXT-2：QL 三查回退链与预览渲染 |
| D-COL2/3 预留（02-04-03） | D-13-CONTEXT-4/5：软打样 override + 多显示器事件面 |
| ViewportFit 单点 + aspectFitUniforms 预留（04-02） | D-13-CONTEXT-6：zoom/pan transform 扩展基座 |
| LayerStack/MaskCombiner 内核（Phase 6） | D-13-CONTEXT-9：蒙版命令面 UI 装配（内核零改） |
| openSession 五步编排 + reconcile（9-1/9-2） | D-13-CONTEXT-7：拖放导入的文件落盘→索引收编路由 |
| Manual-Only 13 行 + F-12-5-2（12-5 移交⑤） | D-13-CONTEXT-10：13-2 同轮 dt-GUI 对照 + 13-4 走查批 |
| XMP 例外集复审位（移交②） | 本 Phase 不依赖三格式内嵌 XMP（lindex 抽取源天然绕开）；复审位转记 Phase 14 |

</code_context>

<specifics>
## Specific Ideas

- **执行顺序刚性**：13-1（appex targets + QL + Spotlight + 探针）→ 13-2（色彩完备，BPC 探针先行）∥ 13-3（交互与 UI 批）→ 13-4（分发收口 + Manual-Only 承接 + 签核）。13-1 的 Tuist 双 target 结构验证（generate + 签名设置 + 宿主嵌入共享 framework）是全 Phase 结构风险根，research 头项就该跑通。
- **research 头项三探针**：①**CG 面软打样可达性**——CGColorConversionInfo rendering intent / **BPC 公开开关存在性**（COLOR-02 唯一可能改变管线形状的未知数；BPC 不可达 = 黑点补偿手做 LUT 或降级注记，须先有结论）；②**QL 渲染时延基线**——100MP RAW headless 渲染 @ 缩略/预览尺寸实测（定 D-13-CONTEXT-2 的超时阈值与回退必要性）；③**Tuist appex 形状验证**——`.appExtension` target 生成、QL/Spotlight extensionPointIdentifier InfoPlist 形状、非沙盒 entitlements、与宿主共享 framework 的 @rpath/签名链。
- **C 档门控**：research 定稿后停（用户过目 Open Questions 裁决点）→ 每 plan 执行+验收闭环后停 → 签核（VALIDATION）前停。worker 每任务边界查 `.work/config.toml [gsd]`。
- **人工阻塞项须早登记**（GOAL-STATE 阻塞节）：Developer ID 证书与私钥、App Store Connect API key、GitHub 公开仓创建/公开时机、GitHub Secrets 配置——13-4 排期前必须由用户供件；research/plan 期即提醒，勿到 13-4 开工才发现断链。
- **敏感审计闸是 13-4 第一任务**：全历史凭证扫描（gitleaks 类工具 + 人工复核内部域名/绝对路径）报告落档后才许任何公开仓操作；「全历史 vs squash 起点」二选一 = 用户裁决位（D-13-CONTEXT-8 默认全历史）。
- **QL 预览的语义边界要在 plan 里显式教**：QL 显示的是**编辑态**（编辑器视口孪生，无 yiyin 印框、无导出 sizing/量化）——不是导出预览；用户预期若是「印框后成品预览」属导出域（Quick Look 不做），UX 文案不得暗示。
- **执行期决策边界**：zoom HUD 形态（百分比指示/滑杆）、proof toggle 入口位置与快捷键、蒙版命令快捷键表、DMG 卷面（v1 素面 UDZO）、CI runner 规格（macos-15/26 镜像选型）、QL 超时阈值具体值——标注执行期决策入各 plan DECISIONS，不臆造。

</specifics>

<deferred>
## Deferred Ideas

- **Sparkle 自动更新框架**——v2；v1 手动下载 + GitHub Releases
- **Spotlight 自定义 schema / 自定义属性**（flag/note/layer_summary 检索）——需要随 app 装 schema + 域重扫；标准属性不覆盖时再议
- **Quick Look 内编辑/评分/标记**——QL 恒只读
- **Metal 快路径软打样（ICC LUT 预采样）**——ColorSync 腿够用则免；拖动热路径出现 proof 需求时再议
- **crop/liquify/retouch overlay 的 zoom 内编辑**——v1 互斥锁 fit；viewportTransform 稳定后逐 host 增量
- **create-dmg 美化卷面（背景图/图标布局）**——v1 素面 hdiutil
- **打印模块 / 地图视图 / 联机拍摄 / 跨 Session 全局搜索**——v2 表既有项
- **IOP-MASK-06 Follow Edges / 07 Depth**——v2 节（ROADMAP :319）；可插队但非本 Phase 承诺
- **XMP 例外集（HEIF/AVIF/WebP）内嵌元数据复审**——移交②转记 Phase 14 同批
- **oslog/diagnose 级 QL 渲染诊断面板**——超时回退日志先落 os_log，可视化后补

</deferred>

---

*Phase: 13-System Integration & Distribution*
*Context gathered: 2026-09-27（discuss 起草；10 项 OQ 全按推荐自动裁决〔晨审追认〕——用户晨间任一推翻即回注 planner 重开受影响面；推翻代价列在追认清单表）*
