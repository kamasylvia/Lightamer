# Alcedo 上游 parity 评估（2026-10 夜间参考仓维护批）

> 范围 = 本地仓 `/Volumes/UNITEK/Documents/Development/AlcedoStudio` ff 后新增区间
> `9ce6a24..7052355`，**142 commits**（任务预估 133，评估时又落 9 个）。纯 ff 零本地分叉。
> 版本面 = **v0.3.2（build 3004，`2fb90a5`）+ 10-09..10-13 主干**；类型分布 fix 37 / feat 24 /
> docs 17 / test 5 / chore 3 / build 1（merge 不计）。
> 上游主叙事：**「CLI、MCP、共享会话自动化计划」（#331，AU1–AU14 全部带实现证据落主干）**
> ——单一 named-command 自动化面，三个消费端（CI 端到端测试 / agent 经 shell `alcedo-cli` /
> agent 经 MCP stdio `alcedo-cli mcp`），两种宿主（`alcedo_main --headless` 无头 / GUI 宿主进程内
> automation server，agent 与用户共享一个应用会话）。正本 plan =
> `docs/roadmap/alcedo_studio/automation/cli_mcp_automation_plan.md`。
> GPL-3.0 只读红线照旧：本文只记功能/交互面与判定，零代码入库。

## 一、主题分组与逐项判定

判定三档：**已有**（我方对应 FEAT id / phase 已交付或超集）/ **立项候选**（REQUIREMENTS V2
「Alcedo Upstream Parity Extensions」追加）/ **注记**（不立项，落观察/质量参考）。

### 主题 A：agent 化 / CLI 扩张（~60 commits，本批主体）

| # | 上游交付 | 上游锚 | 判定 | 依据 |
|---|---|---|---|---|
| A1 | JSON-RPC 协议 + 命令注册表 + 本地 socket server | `7348201` | **已有（形态等价）** | 我方 Phase 14 MCP server 已交付（MCP-01..09，2026-09-28）：McpToolRegistry + HTTP transport + Bearer 鉴权 + endpoint file + launcher；M6-1 补项目级单写者锁 + connect 指引。传输形态不同（QLocalSocket vs HTTP/loopback），能力面等价 |
| A2 | `alcedo-cli` 客户端 + automation session 文件 | `bad3b20` | **已有（形态等价）** | 我方 McpLauncher（一键拉 agent）+ 无头实例 `--project` 仲裁即同位物；CLI 单发命令壳属包装层，无独立需求 |
| A3 | headless `alcedo_main --headless` 会话 + 生命周期命令 | `63876d9` `1b31c86` | **已有** | 我方 MCP 无头模式（M6-1 无头 `--project` 仲裁两臂 + 后台会话）覆盖 |
| A4 | project create/open/save/close 命令 | `fa9b703` | **已有** | 我方 MCP project 面 + M6-1 打开权单写者（撞活实例拒写并转发指引）；GUI 只读回退已交付 |
| A5 | library 命令族：import / read / thumbnail / task；selection / delete / rating | `1e8decd` `f514ad3` | **大部分已有** | 我方 list_photos（FilterPredicateGroup 过滤）/ get_thumbnails / set_rating / set_flag / set_color_label / set_keywords 已交付。缺口 = MCP 删除命令（有意不做——危险面，agent 删片走 GUI 更稳），注记维持 |
| A6 | **editor.catalog 参数目录**（scalar 13 字段起步 → RAW decode / geometry / DT / WB / HLS / 色轮 / curve / LUT 全目次；UI 单位 + range + default + step + owner node；域外拒绝不钳制） | `c8095cc` `a111ebf` `ae55a43` `44a5ce0` `cc7422b` `822ae9e` | **已有 + 覆盖差注记** | 我方 IopCatalog（14-2 T3 手写表 + 反射 guard）即同构物；覆盖决策 D-14-2-T3-1 有意排除 payload/geometry/denoise 族（「extend additively」纪律在案）。上游本批把目次扩到全面板，验证了「agent 需要全字段目次」方向——我方扩面时机 = agent 编排实际需要时按既有纪律加，guard 测试兜真；不立项，IopCatalog 维护项 |
| A7 | editor.get/editor.set + render.preview + 字段→owner node 解析 + get→set round-trip 修复 | `030526a` `822ae9e` `daf1948` | **已有** | apply_params / list_iops / render_preview 全交付；round-trip 修复（get 值须可 set 回）= 我方 IopCatalog 版本 guard 同职责，质量参考 |
| A8 | versions 命令（branch / checkout + commit attribution；`from_commit` 先验拒绝） | `cd3b4e4` `34b57ad` | **已挂账（MCP-09-B）** | 我方 M2-8 版本链在 app 侧交付；MCP versions 面早已是 MCP-09 研究项 B（多版本参数组/历史快照 MCP 语义，未决）。上游实现验证需求真实 + `from_commit` 未知名先验拒绝是好细节，M6+ 兑现 MCP-09-B 时取用 |
| A9 | export 命令 + search 命令（search.session 移 C++ + search.query） | `2ea9432` `1b6434e` | **已有** | export_image / list_photos 过滤已交付；EXIF 结构化检索（ExifSearchParser）+ CLIP 语义检索均已交付 |
| A10 | **agent GUI turn-taking 控制**（agent 与用户轮流操作 GUI 会话 + 编辑期间 scopes 保活 `c7ba784` + task island 会话钉住 `7e0c9cb`/`039e7b8`） | `a6c8848` | **注记（不立项）** | 我方选定的 agent 路线 = MCP 编排皮（GUI 交互与 agent 编排并存不冲突，MCP-09 注记在案）。GUI turn-taking 是 UI/AX 重资产面（交互锁、任务岛 UI、焦点仲裁），零用户需求前不立项；「agent 操作时 scopes/diagnostics 后台通道保活」质量点记录 |
| A11 | contact sheet / 批量缩略图（library.thumbnails ≤1000 张 + library.info + `alcedo-cli batch` stdin 批处理） | `6a0fe59` | **已有** | get_contact_sheet / get_thumbnails 已交付；stdin 批处理是 CLI 包装层细节 |
| A12 | adjustment copy/paste 批量命令（含「包未复制的条目保目标默认值」修复 `9f9fc5e`） | `e75cf2a` | **已有** | 我方 Copy Adjustments（M2-8，isAdjustmentTransferable 单谓词 + 排除面单源）+ MCP apply_params fan-out；「未复制条目保目标默认」语义与 M2-8 排除面同构 |
| A13 | lut.list | `e015066` | **已有** | 我方 LUT 库面（M2-5/M3-1）+ MCP 预设族同域；list 型工具属既有面自然延伸 |
| A14 | `alcedo-cli` 随包安装（Win/macOS） | `6721227` | **已有/不适用** | 我方 MCP HTTP 面无随包 CLI 需求；launcher 即入口 |
| A15 | automation 文档面（alcedo-cli reference 生成器 + skills 链接化） | `2b943fa` `5846be6` `3d30062` 等 | 注记 | 文档工程，无 parity 面 |

**主题 A 总判定**：Alcedo 自动化面整体是我方 Phase 14 + M6-1 已交付能力的**同构追认**——
三端一缝、双宿主、单写者仲裁我方均已落（部分更早：M6-1 单写者锁 2026-10-14 vs 上游 AU 批
2026-10-09..13）。真正缺口只有两处半：**MCP versions 面（已是 MCP-09-B 挂账）**、
**IopCatalog 覆盖面（既有 extend-additively 纪律内）**、GUI turn-taking（明确不立项）。
方法论可取：**参数目录「域外拒绝不钳制 + 报合法 range」**（A6 细节）与
**`from_commit` 先验拒绝**（A8 细节）——两处都是「typed 拒绝优先于静默钳制」同款纪律，
兑现 MCP-09-B / IopCatalog 扩面时照抄。

### 主题 B：导出 / 元数据 / 解码（修复为主）

| # | 上游交付 | 上游锚 | 判定 | 依据 |
|---|---|---|---|---|
| B1 | **导出面板预设化**（全导出选项命名预设 + EXIF 元数据 / ICC profile / GPS 位置三勾选） | `7052355` | **立项候选 = EXPORT-PRESET-01** | 我方 M2-9 导出页有逐项记忆键族（质量/命名模板/目录），无「全选项命名预设」层；源 EXIF/GPS 保留语义我方 ExportMetadataPolicy STANDARD 已覆盖（含 location/serials 剥离勾选同构），缺口仅在**预设层**。Alcedo 对标 = UI 完全模仿，此为真 UI 面。候选形态见第二节 |
| B2 | 源 EXIF/GPS/IFD0 经导出保留（JPEG/UltraHDR/TIFF/PNG/EXR） | `7052355` | **已有** | ExportMetadataPolicy STANDARD（M2-9-02）同语义；其「不复制尺寸/方向/缩略图/色彩空间/LR 调参」排除集与我方一致方向 |
| B3 | 记住上次导出目录 | `dd5fe3b` | **已有** | `export.lastDirectory`（M2-9-04，OQ-3）逐字节同语义 |
| B4 | OpenDRT 补 sRGB 输出 | `6b4ca51` | **已有** | 我方 `DrtEotf.srgbPiecewise`（M4-1-01 T9，kernelIndex 7，legalEOTFs rec709/p3d65 链首）已交付——双方独立同补，互为对表 |
| B5 | Nikon 无色彩矩阵 NEF 识别 | `586ffaf` | **不适用** | CIRAW 解码域（Apple 名单内机身）；Alcedo 自养 LibRaw fork 的修补，我方无需 |
| B6 | capture time 从 EXIF 日期文本读相机钟（墙钟 vs 本地时区） | `3050cc2` | **注记** | 时区/墙钟语义坑；我方 ExifFold 摄取时间域 walkthrough 观察项 |

### 主题 C：编辑器质量修复（质量参考，全注记）

| # | 上游交付 | 上游锚 | 我方落点 |
|---|---|---|---|
| C1 | **HLS / 色轮默认值 = 面板写路径**（默认值漂移致读写不对称） | `d3f4680` | 我方 GradeCatalog 七新件（M2-2 批 colorWheels/hls 等）walkthrough 观察项：默认值须与面板写路径同一常量源 |
| C2 | **curve 点域校验**（单位方形外/乱序点拒绝） | `97dbf1e` | 我方 tonecurve 用 monotoneHermite（x 单调性求解期强制），但**写入口的域校验（单位域外/乱序拒绝）**列 walkthrough 核对项 |
| C3 | persistInFlight 从 persist 结果清除（latch 卡死） | `a91dc3a` | 我方 sidecar 2s debounce + flushNow 同域防 latch 卡死参照 |
| C4 | executor owner thread id 先于 worker 启动初始化 | `3d30062` | 线程竞态模式参照 |
| C5 | 批量渲染 Execute 失败时释放批 GPU 资源 | `70db9ba` | 我方导出队列失败路径资源释放核对项 |
| C6 | 缩略图各 tier pin 归属各自消费者 | `d813f92` | 我方 PipeCache/缩略图缓存 pin 语义参照 |
| C7 | import 修复三件（取消跳过已排队 / 分类映射+栅格元数据 / RAW 与其他文件分离进度环） | `70dae5d` `577d404` `5aec12c` | 我方 ImportService 分账已有（excludedType 等）；分离进度环为 UX 细节注记 |
| C8 | editor 命令渲染失败仍应答 | `e35bd78` | MCP 工具失败应答纪律——我方 typed 错误面已有 |
| C9 | Version checkout reply 在其帧之后发送 / QML 小写信号孪生 / 死参数补丁代码清除 | `847dd95` `33141d3` `fbe129d` | Qt/QML 特定，N/A |
| C10 | 项目未进入时 project.open 命名 / library 全选查询域 + worker 删除 | `ba54488` `0629b3c` | 命令面细节，无独立 parity 面 |

### 主题 D：打包（打包经验，全注记）

| # | 上游交付 | 上游锚 | 我方落点 |
|---|---|---|---|
| D1 | OpenMP runtime 显式入 macOS bundle + 构建树日志不入包 | `c18a664` | 「运行时库须显式入 bundle」与 2026-10-08 增补已登记的 `display_to_ap1.metallib` 教训同类；我方 Tuist embed 面已按此纪律 |
| D2 | OpenCL kernel 共享头入包（DisplayToAp1 program） | `0302935` | 同上，资源完整性教训同类；我方零 OpenCL |
| D3 | DMG detach 重试 / Windows 隐藏控制台 | `dfbf37b` `ca1f863` | CI/Windows 特定，N/A |
| D4 | Exiv2 XMP toolkit 主线程先于 worker 初始化 | `b027a85` | **N/A 但方法论通用**：第三方元数据库的进程级 init 必须先于并发 worker 读——我方 ImageIO 无此坑；若未来引入任何 C 库元数据层照此 |

## 二、立项候选（REQUIREMENTS V2 节追加）

**EXPORT-PRESET-01**（唯一新候选，小件）：

- **需求**：导出面板命名预设层——把格式/质量/位深/sizing/元数据策略/ICC/命名模板整组
  存为具名预设，Export 页一键套用；内置默认预设 + 用户预设管理（增删改/排序）。
  对齐上游 `7052355` 形态（全选项预设 + EXIF/ICC/GPS 三勾选随预设走）。
- **判定依据**：「UI 与功能面完全模仿 Alcedo」charter 下这是真实 UI 面（上游 2026-10-14 新增）；
  我方既有逐项记忆键族（`export.*Quality` / `export.namingTemplates` / `export.lastDirectory`）
  是预设层的数据基座，加层不加键族冲突。
- **建议站点**：V2 站裁量（M7+ 导出打磨批）；不阻塞任何在飞 phase。

## 三、质量参考清单（walkthrough / 未来兑现取用）

1. MCP-09-B 兑现时：`from_commit` 先验拒绝（`34b57ad`）+ Version checkout 回复时序（`847dd95`）。
2. IopCatalog 扩面时：参数目录「域外拒绝 + 报合法 range，不钳制」（`c8095cc` ToModelJson 语义）。
3. GUI 走查：GradeCatalog 默认值 ≡ 面板写路径（`d3f4680`）；tonecurve 写入口点域校验（`97dbf1e`）；
   导出失败路径 GPU 资源释放（`70db9ba`）。
4. 时区语义：capture time 墙钟 vs 相机钟（`3050cc2`）——ExifFold 观察项。
5. 若引入 C 库元数据层：进程级 init 先于并发 worker（`b027a85`）。

## 四、锚与对账

- 上游区间：`9ce6a24`（v0.3.1+主干基线，前批测绘终点）→ `7052355`（HEAD，2026-10-14）。
- 前批测绘正本：`ALCEDO-FEATURE-MAP.md`「上游增量测绘」节（2026-10-07/08 两批）；
  本文件为其续批。stable-ID 对账正本仍 = `docs/parity-checklist.md`（FEAT- 体系）。
- 上游 automation plan：`docs/roadmap/alcedo_studio/automation/cli_mcp_automation_plan.md`
  （AU1–AU14，source revision `f03ece5df`）。
- 本地仓状态：main = `7052355`，origin/main 同步，工作树干净。
