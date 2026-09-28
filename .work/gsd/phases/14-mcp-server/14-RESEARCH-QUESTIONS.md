# Phase 14: MCP Server — Research Questions

**Created:** 2026-09-28（discuss 环起草；给 research 环的问题清单，答案落 `14-RESEARCH.md`）
**输入:** `14-CONTEXT.md`（D-14-CONTEXT-1..12 + Phase Boundary）+ ROADMAP §Phase 14（:258-269）+ REQUIREMENTS MCP-01..10（:477-488）+ 12/13 移交面（14-DISCUSSION-LOG 重构五条）
**约定:** 每条 RQ 给「问题 / 为什么 / 验证方法 / 关联裁决」。P0 = 阻塞 plan 划界的答案；P1 = plan 内可并行解决。带 ★ 的 = **research 首探针项**（本 discuss 环未跑探针/构建，探针留给 research——SDK 集成与 parity 两项是 14-1/14-2 划界前提）。

---

## A. 底座：SDK / 传输 / 并发（P0——14-1 划界输入）

### RQ-14-1 swift-sdk 集成探针（P0 首位）★探针
- **问题**: ①swift-sdk 0.12.1 在本仓 Tuist 工程（Swift 6/macOS 27）的 SPM 依赖图与编译实况（swift-nio 传递依赖与既有 target 无冲突；build 时长增量）；②**stdio hello-world 端到端**——`MCPServer` stdio 宿主跑通 initialize/tools list/tools call（用真实 MCP client 如 `claude`/手写 JSON-RPC 脚本对打）；Streamable HTTP 宿主同测（127.0.0.1 绑定 + Origin 403 行为实测）；③**headless 进程可行性**——同 binary（SwiftUI `@main`）经启动参数跳过 UI 主循环跑 server 的实测（NSApplication 不 run 的副作用；回退 = executor 新 target 的代价评估）；④0.x API 稳定面评估（0.10→0.12 breaking 变更谱——pin 升级成本基线）。
- **验证**: 一次性探针工程/分支（不进 main）；hello-world 双传输脚本 + 编译日志落档；headless 实机试跑。
- **关联**: D-14-CONTEXT-1/2；14-1 划界前提（探针不过 → 划界重谈）。

### RQ-14-2 端点发现文件协议与宿主细节
- **问题**: `.lightamer/mcp-endpoint.json` 精确 schema（host/port/token 指纹/pid/started_at/health 字段集；token 全量入文件还是指纹 + keychain 取真身——安全权衡）；文件落位（app 支持目录全局一份 vs per-session——推荐全局）；写删时序（启动写/优雅停删/崩溃残留检测 = pid 存活校验）；stdio 宿主是否也写发现文件（推荐：写——launcher 统一发现通道，但 token 字段语义按宿主定）；server info/capabilities 声明两宿主差异。
- **验证**: schema 设计推演 + RQ-14-1 探针宿主实测写删时序；与 `SmartAlbumStore`/`YiyinFontStore` 的 app 级资产存储范式对齐（三拆模式）。
- **关联**: D-14-CONTEXT-2；RQ-14-3（锁同文件族）。

### RQ-14-3 研究项 A 终判——单写者机制与 GUI-live 判据
- **问题**: ①**GUI-live 判据精确来源**——PipeCoordinator 活动集的代码形态走查（哪张图在编辑器打开/正在拖滑块的状态位；「打开」与「脏」两级是否区分——推荐只拒「打开中」）；②锁原语终判——端点文件 `O_EXCL` 创建 vs `flock`（崩溃残留处置：O_EXCL 需 pid 校验自愈，flock 内核持有无残留——倾向 flock）；③后开者只读降级的工具级行为（写工具 typed error 文本与错误码表；`tools/list` 是否随模式变化——推荐不变，错误在 call 时给）；④SidecarStore 2s debounce 与 MCP 写回的汇合（MCP 经 MetadataService/批量管线走 claim 面，不经 SidecarStore 直写——确认无第三条写路径残留）；⑤MCP render（读 sidecar）与 GUI 写 sidecar 的读一致性（渲染中 sidecar 被写 = 读到半新半旧？——读时快照语义）。
- **验证**: PipeCoordinator/SessionState 代码走查 + 锁原语小探针（两进程互斥实机测）+ 时序推演表。
- **关联**: D-14-CONTEXT-5（预裁主形态）；Boundary 事实 3。

## B. 修图面（P0——14-2 输入）

### RQ-14-4 render_preview 形状与 MCP-03 parity 测试形态 ★探针
- **问题**: ①ExportRenderer 参数化变体的精确差异面（不落盘 → inline 编码；尺寸/格式参数插在哪一段——渲染后 CGImage 缩放 vs 管内 PREVIEW 平面；JPEG 质量默认值）；②**MCP-03 parity 初测**——同 sidecar 同参下参数化变体 vs Export golden 族输出对照（像素级 or 容差口径随 11 期先例；尺寸缩放引入的重采样差异如何口径——推荐 parity 门在「同尺寸同参数」域钉，缩放域只做内容断言）；③渲染超时/取消语义（QL 有界超时先例数值；MCP 请求级超时表——render 最长）；④L014 fence 腿确认（读回路径复用 Export 的 R8 fence 先例）。
- **验证**: 探针 = 参数化渲染变体 + golden 对照跑通一例真 RAW；超时注入测试形态设计。
- **关联**: D-14-CONTEXT-7；SC#3 字面；13-1 QL parity 测试模板。

### RQ-14-5 apply_params / 活动上下文工具面设计（最难 schema 面）
- **问题**: ①`apply_params` 入参 JSON 形状终判——iop `Params` Codable 类型直映（镜像一份 JSON schema，手写或 CodingKeys 反射生成）vs 扁平 `{op, params}` dict + registry 校验；图层栈操作语义（additive 单模块 set / replace 整栈 / patch 多模块批量——推荐三动词合一工具多操作子？还是拆？——推荐 apply_params = 模块级 upsert + `reset_params` 位；整栈操作走 apply_preset 通道）；②模块实例寻址（op 名 + multi_name/multi_priority——history identity tuple 的 MCP 面）；③**活动上下文落盘时机**（apply 即写 = 与 GUI 同构【推荐】 vs 显式 commit 工具；apply 即写时 render_preview 读盘 = 一致性天然成立）；④load_image 的上下文生命周期（切换图/关闭/超时回收）；⑤错误面（未知 op/参数越界/类型不匹配的 typed error 码表）。
- **验证**: schema 设计推演 + 与 `ModuleInstance`/history identity（Phase 2 契约）对照表；golden 往返一例（apply → 读盘 sidecar → 字节面验证）。
- **关联**: D-14-CONTEXT-7④/11；SC#1。

### RQ-14-6 iop 清单/schema 元数据工具（list_iops）
- **问题**: list_iops 返回面（op 名/display 名/iop_order/Params 键集与类型/适用域 raw vs non-raw——registry 遍历来源；Params schema 从 CodingKeys 反射生成的可行性探针 vs 手写 schema 表的维护成本）；版本漂移表达（iop version 字段是否暴露——推荐暴露供 agent 缓存失效）。
- **验证**: registry 反射小探针（Mirror/CodingKeys 遍历一例 Params 类型）。
- **关联**: D-14-CONTEXT-3①；MCP-01「iop 清单与参数 schema 元数据」字面。

### RQ-14-7 list_photos 入参与轻量列终表
- **问题**: ①入参 = `FilterPredicateGroup` JSON 直作的 schema 细节（谓词字段 16 白名单全暴露 or 子集；`FilterSortKey` 六键枚举直映；limit/cursor 分页形状——keyset 游标字段 = capture_date+path 与 16 期 RQ-16-6 同源）；②**轻量列终表**——MCP-05 黑体「EXIF 轻量列/rating/flag/has_edits」逐列落 34 列子集（推荐：34 列全暴露但分组标轻量/完整，缩略图路径类列除外——终表 = research 产出直进 14-3 PLAN）；③返回结构（行数组 + 总数面——count 的代价；16 期 COUNT 语义对照）。
- **验证**: 列清单对照 `SessionIndexSchema.swift:66-102` 逐列过（每列「暴露/不暴露+理由」表）；谓词 JSON 往返一例（同一 FilterPredicateGroup GUI chips 与 MCP 入参同结果）。
- **关联**: D-14-CONTEXT-8①；12 移交③；34 列 frozen 契约（13 移交②——列名拼写零改动）。

### RQ-14-8 图像三件套参数与 base64 预算表 ★探针
- **问题**: ①get_thumbnails：双档直读语义（档 A embedded 解码 + 档 B 磁盘 JPEG 直读；thumb_state=3 stale 行为终判——推荐默认返回 stale 标记 + `regenerate` 可选参数触发 tier B 单图重渲）；批量上限（N 张/请求）；②get_contact_sheet：布局参数（N×M/cell size/背景/标注行内容与字体——标注 = 文件名+星级最小面）；拼图实现（CoreGraphics 绘制，无管线依赖）；③get_detail_crop：ROI 坐标系（原图像素）；下采样上限；多 ROI 单请求？；④**base64 预算表**——四工具 × 默认/上限分辨率 × JPEG 质量档 → 输出字节数表 + LLM token 粗估（每图 ~bytes×4/3 base64 膨胀 × token/bytes 系数）——**默认值由预算表定**，不是拍脑袋（render_preview 默认 1024？contact sheet cell 256？100 张缩略图一批的总量口径？）。
- **验证**: 探针 = 真实样张四工具输出实测字节表；预算表落档 `14-RESEARCH.md`。
- **关联**: D-14-CONTEXT-4/8；SC#5 筛选端到端的可用性底座。

### RQ-14-11 export_image 复用面（P0，14-2 输入）
- **问题**: ①落盘通道终判——直渲（ExportRenderer 变体 + 编码 registry + L009 晋升）vs 入 ExportQueue job（进度/取消/并发 1 队列语义——单图导出走队列是否过重；推荐直渲 + 渲染信号量，队列语义留给 GUI 批量）；②yiyin 参数位（默认关/显式开——D-14-CONTEXT-7②；开时的注入器缝 = App 层 `ExportYiyinInjector` 生产注入器复用）；③输出位置与命名（限 Session/Output/ 域；重名处理 = Phase 11 tag 派生 `<stem>_<tag>` + `-1` 递增先例照抄）；④路径返回语义（绝对路径文本；client 无法读远程盘的提示语）。
- **验证**: 代码走查（ExportQueue/ExportFileWriter/命名派生消费面）+ 一例真实导出往返（MCP call → 落盘 → 字节面核对）随 14-2 交付。
- **关联**: D-14-CONTEXT-4③/7②；MCP-09；EXP-01..08 面复用边界。

## C. 筛选辅助与安全（P0/P1——14-3 输入）

### RQ-14-9 burst 分组算法（P1）
- **问题**: 聚类键终判（capture_date 间隔阈值——默认 2s 参数化；camera_model 参与否【换机不并组——推荐参与】；跨日 burst 边界）；返回形态（组 id + 成员 rel_path 数组；与 list_photos 的组合查询——burst 内过滤）；lindex 查询形状（ORDER BY capture_date 单扫内存聚类 vs SQL 窗口——万张级内存聚类够）。
- **验证**: 真会话 burst 样张聚类试跑（阈值敏感性目检）；性能不设门（查询层量级）。
- **关联**: D-14-CONTEXT-8⑤；SC#6。

### RQ-14-10 get_face_regions 复用面（P1）★探针
- **问题**: SkinRegionLocator 复用形状（其编排含 hull/保护区逻辑——脸框只需 VNFaceLandmarks2D/VNDetectFaceRectangles 轻请求，是否直接用 Vision 请求而非整套 SkinRegionLocator；推荐：轻请求直用，SkinRegionLocator 是磨皮域孪生不硬套）；**批量成本计量**（单图 Vision 延迟实探；万张场景的按需触发与缓存策略——脸框缓存位：lindex 列？内存 LRU？——推荐 per-request 不缓存 + 文档标注成本，缓存 additive）；无脸图语义（空数组非错误）。
- **验证**: 探针 = 10 张含人脸样张脸框请求延迟与坐标质量实measured；无脸负例。
- **关联**: D-14-CONTEXT-8⑥；SC#6「脸部区域定位」；Phase 7 基建。

### RQ-14-13 安全细节（P1）
- **问题**: token 生成（熵源/长度）与存储位（keychain vs 0600 文件——推荐 keychain，fallback 文件；launcher/外部 client 如何取得 = 发现文件指纹 + keychain 服务名，还是 token 直入发现文件 0600——权衡便利性，research 定并给安全走查口径）；Origin 校验实测（RQ-14-1 探针内）；非回环绑定的监听接口选择（0.0.0.0 vs 具体网卡——推荐 0.0.0.0 + 文档明示）；速率限制 = 渲染信号量的参数化（并发 1）。
- **验证**: 机制推演 + 14-4 安全走查清单草案（公开仓审计注意项——Boundary 事实 6）。
- **关联**: D-14-CONTEXT-6；MCP-04/08。

## D. launcher 与收口（P1——14-4 输入）

### RQ-14-12 launcher 细节（P1）
- **问题**: 默认命令模板示例文案（pi/omp 各一条真实可跑样例——端点发现文件的 agent 侧消费方式示例）；`{{PROMPT}}` 转义规则（shell 单引号包裹内双转义——模板语义文档化）；日志面板形态（环形缓冲行数上限/暂停滚动/导出）；进程终止 UX（cancel 按钮 → SIGTERM → 5s → SIGKILL；§8.5 自家子进程纪律的 UI 呈现）；launch 失败/非零退出/写回零结果的反馈面。
- **验证**: UX 推演 + 真实 agent CLI 一次手动拉起走查（Manual-Only 候选）。
- **关联**: D-14-CONTEXT-10；SC#7。

### RQ-14-14 生命周期/超时/多 client（P1）
- **问题**: 请求级超时表（各工具类：元数据 ms 级/缩略图 s 级/render 最长——与 QL 有界超时数值族对齐）；server 停机时 in-flight 请求处置（优雅排空 vs 即断——GUI 开关切停/`applicationWillTerminate` 路径）；HTTP 多 client 并发上限；活动上下文的 client 归属（两 client 轮流 load_image = 上下文互踩——推荐上下文全局单份、后 load 覆盖前 + 错误面提示；或 per-client 上下文——成本高，research 定）。
- **验证**: 时序推演 + 双 client 并发小探针（RQ-14-1 探针扩展）。
- **关联**: D-14-CONTEXT-2④/5⑤。

### RQ-14-15 研究项 B/C 终判登记 + 复审位处置（登记型，晨审知悉）
- **问题**: ①研究项 B 的 v2 登记形态（CONTEXT D-14-CONTEXT-11 预裁「history append 既有语义 + 版本面 defer」——research 复核 GUI history 遍历确实可承担「回退到任意历史点」（HIST-02 已交付语义），确认 MCP 不暴露 history 工具无功能洞）；②研究项 C 零占用确认（tools/list 快照不含 match_color；V2 TRACK 落地时的 additive 入集流程留痕）；③XMP 三格式复审位**关闭**的留痕（12 移交②经 13 转记——处置理由：v1 元数据真身 sidecar/lindex 不经内嵌 XMP；复审条件不成立）；④WebP mux 复审位沿用 11 期降级注记（MCP export_image 不新增工作）。
- **验证**: 无探针——登记 + HIST-02 语义对照。
- **关联**: D-14-CONTEXT-11；CONTEXT deferred 节。

---

## 优先级与研究环顺序建议

| 序 | RQ | 优先级 | 类型 |
|---|---|---|---|
| 1 | RQ-14-1 SDK 集成 + 双传输 + headless 探针 | P0 | ★探针（14-1 划界前提） |
| 2 | RQ-14-4 render_preview 形状 + parity 初测 | P0 | ★探针 + 设计 |
| 3 | RQ-14-5 apply_params/上下文 schema | P0 | 设计（最难工具面） |
| 4 | RQ-14-3 研究项 A 终判（GUI-live 判据 + 锁原语） | P0 | 走查 + 小探针 |
| 5 | RQ-14-2 端点发现协议 | P0 | 设计 |
| 6 | RQ-14-7 list_photos 入参/列终表 | P0 | 设计 |
| 7 | RQ-14-8 图像三件套 + base64 预算表 | P0 | ★探针 + 设计 |
| 8 | RQ-14-6 list_iops schema 生成 / RQ-14-11 export_image 复用面 | P0 | 设计 + 小探针 |
| 9 | RQ-14-13 安全细节 | P1 | 设计 |
| 10 | RQ-14-10 get_face_regions 成本 | P1 | ★探针 |
| 11 | RQ-14-9/12/14（burst/launcher/生命周期） | P1 | 设计 |
| 12 | RQ-14-15 研究项 B/C/复审位登记 | 登记型 | 对照 |

---

*Phase: 14-MCP Server — Research Questions*
*起草: 2026-09-28（discuss 环；本环未跑探针/构建——★ 三项为 research 首探针，探针脚本与数字落 14-RESEARCH.md）*
