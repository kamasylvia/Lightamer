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
- 本地仓状态：main = `6024386`（2026-10-16 ff，见 §五），工作树干净。

## 五、2026-10-16 增量（`7052355..6024386`，+19）

> 夜间同步批：SSH fetch（HTTPS 代理死）→ 干净树 ff-only，`7052355..6024386` 零冲突。
> 上游 2026-10-14..10-15：**v0.3.3 发布**（`457d6d8` release notes + 版本号）+ 2 主干 commit。
> 主题面收敛——无新特性叙事，全部为自动化面收尾杂务 + 导出/呈现缺陷修复。

### 逐 commit 判定

| 上游锚 | 交付 | 判定 | 依据 |
|---|---|---|---|
| `36db9a8` | export ICC：macOS 嵌入 γ2.2/2.4 自建 profile + **预览层改挂导出同款 profile**。根因 = CG named space 无纯幂曲线（此前导出被 ITUR_709/sRGB 代理曲线顶替，预览标 SRGB 却报精确匹配，#391） | **已有（导出半）+ 入队候选（预览半）** | 导出嵌入：我方 L053 `DrtOutputColorSpace` SDR 幂臂自建 ICC v4 字节，同判同解且更早。预览标注：我方 DRT-SDR 层挂 `CGColorSpace(calibratedRGBWhitePoint:...)` 近似（EditorMTKView `drtLayerColorSpace`，srgbPiecewise 更以 2.2 幂近似分段曲线），导出文件却携 ICC v4——**正是上游此修的失配类**。候选 = 层 colorspace 改 `CGColorSpace(iccProfileData:)` 挂导出同款字节 + ColorSync 解码等值测试；小件，UQ-A1 |
| `6203791` | FAIL 冲突档一步原子不覆盖：`renameatx_np(RENAME_EXCL)` / `renameat2(NOREPLACE)` / `link()+unlink()`，exists() 预检移除（TOCTOU） | **入队候选** | 我方 `.fail` = occupiedNames 快照检查（ExportNamer.destinationURL）+ 编码器直写目标路径——快照与落盘之间他进程建文件即被覆盖，同款 TOCTOU。候选 = FAIL 档终写改排他晋升（tmp 编码 + `link()` EEXIST 拒绝 + unlink）；小件，UQ-A2 |
| `fedbc9c` | 窗口最小化即拒帧、还原续渲（自研 presenter sink 在最小化时 map 写目标 5s 挂死 + 还原后无人重渲，首帧被拒即会话 Failed） | **注记（不立项）** | 架构差：Alcedo 自研 sink 多槽仲裁有「consumer off 无界等待」结构缺陷；我方 MTKView/CAMetalLayer 标准呈链无此形态。观察项：最小化期间长导出 → 还原首帧正确性，入 GUI 走查清单即可 |
| `1f12551` | 自动化输出不覆盖：library.thumbnail(s)/render.preview 排他创建（NewOnly），失败清理自建文件 | **注记（不立项，纪律挂未来面）** | 我方 MCP 面无 thumbnail/preview 生成命令；「排他创建 + 失败清理自建物」纪律入 UPSTREAM-QUEUE 未来面节，MCP 扩面时吸收 |
| `c1a66b4` | session-prune 只删自家陈旧会话记录，不动其它文件 | 注记 | 我方 `.lra`/`.lalb` 无 prune 面；将来若建，「只删自家记录」由 sidecar 隔离设计天然满足 |
| `cbba564` | background-tasks agent 会话卡片随任务列表滚动 | 注记 | Alcedo agent GUI 专属 |
| `ace755e` | `alcedo-cli --version` 打印版本 | 注记 | CLI 壳未立项；若建照抄旗标惯例（入 UPSTREAM-QUEUE 未来面节） |
| `829832d` + `6024386` | Dawn（WebGPU）submodule 移除 + 构建残留清理 | 注记 | Alcedo 第三方构建卫生，与我方无关 |
| `457d6d8` + `34025e1` | v0.3.3 release notes + 版本面 | 注记 | docs |
| `560f9f6` | gitignore 本地 docs examples | 注记 | 无关 |
| `ee381a8` `a8ea591` `55676d1` `c6d44e2` `acb6e49` `5a92008` `3aa854b` | 上表各项的 merge commit | — | 不单独判定 |

### 分布汇总

**已有 1**（`36db9a8` 导出嵌入半，L053 先行）；**入队 2**（UQ-A1 预览层同 profile 标注、UQ-A2 FAIL 原子不覆盖终写——均小件，落 `research/UPSTREAM-QUEUE.md`）；**不立项/注记 16**（含 merge 与未来面纪律两条）。无新 REQUIREMENTS ID。


---

## 增量节二：+138（2026-10-13..10-25，v0.3.2..v0.3.4 主干；M9 charter 输入批，2026-10-25）

> 范围 = `7052355..origin/main`（本地 checkout 落后，经 origin/main 读）。类型分布
> feat 55 / fix 38 / docs 30 / test 5 / merge 10。上游主叙事 = **「AI Segmentation Mask」
> （0.3.4 主功能，#447 master plan + SM1-SM9 十六子阶段，~90% 增量）**；副线 =
> color wheels LGG 语义修订、filmstrip 过滤器跟随、search palette、LUT encodings
> +24、解码器/镜头库更新。正本判定已入 `M9-CHARTER-INPUT.md`（候选站/OQ/排除），
> 本节按 parity 三档逐主题记账。

### 主题 B：AI Segmentation Mask 工具（SM1-SM9，~110 commits）

| # | 上游交付 | 上游锚 | 判定 | 依据 |
|---|---|---|---|---|
| B1 | 模型集选型定案：SAM 2.1 Hiera tiny（Apache-2.0，macOS CoreML 134+21MB）+ people_sky_head（自有，1.1MB）+ S3OD s3od-synth（MIT+DINOv3，271MB）；EfficientSAM3/SAM3 弃用 | master plan §8.2 | **不跟（路线豁免）** | 我方 macOS 27 `GenerateIterativeSegmentationRequest`（AIMaskService Layer B）原生交互分割已建成；Alcedo 引模型是 Windows DirectML 跨平台需求。427MB 模型 + 3.19GB 内存 + sidecar 进程全免付。OQ-M9-1 |
| B2 | sidecar 分离进程推理（Rust puerh_mind + gRPC 持久通道）+ 闲时停/按需载（U6）+ S3OD 常驻（D22）+ embedding 缓存 4 张 | `ce66fd2` `4cae651` `6a52abf` | **不适用** | Vision 进程内推理，无 sidecar 治理面；按请求载卸天然满足 |
| B3 | 任务蒙版四件 Subject/Background/Sky/People（S3OD Subject，Background=反转；head 定位 Sky/People；People = person box 裁切 S3OD 逐人加减） | `cc7c7d3` `6ad7e7b` | **立项候选（站 1 主料）** | 我方 subject（Layer A）/person（实例级）已有；**Background = 1−Subject 纯逻辑即加；Sky 无原生 API（OQ-M9-2：砍/引 EfficientViT-Seg/启发式三选）**；无任务面板入口 |
| B4 | 分析渲染 ReferenceSpace（无 crop/rotation，D7/D8）+ 视口坐标→prompt 映射 | `b8b9675` | **已有（语义等价）** | 我方 SegmentEditingOverlayHost 全解码帧归一化坐标 + `AIMaskPoint.visionPoint` 单缝 Y 翻转（07-3 T2）；几何指纹失配提示（D9）我方未做，站 1 小件 |
| B5 | AI Mask 编辑会话两级 history（session 内存栈 + Commit 单发布 + Cancel 零发布 D16）+ R8 coverage asset 内容寻址（D17）+ Feather/Expand 为 source 字段（D20）+ paste 跳过 AI Mask（D18） | `96ff8cd` `98909ed` `4bde35a` | **立项候选（形态取舍）** | 我方 bake-to-raster 范式（AI-06 非黑箱：参数不持久、像素即真相、confirm=1 条 stackSnapshot）更简；**真差距 = 会话内 undo/redo 直通主 history（无 session 栈）+ 无候选保留/失败 Retry 面**。站 1 按「SegmentSession 内存栈 + live 候选 tint」吸收，不引 R8 asset（范式已定，charter 显式声明合法偏离） |
| B6 | GPU Feather/Expand（三后端，coverage texture 生成期应用） | `038af91` `4f12146` `57dc80d` | **半已有** | Feather ±100 双腿已有（AIMaskFeather KD-3，GPU Deriche + logit-gain）；**Expand 缺**——站 1 形态学膨胀接 GPU bake 缝 |
| B7 | coverage 专属视口通道（RGBA32F 红通道）+ 淡红 tint（#515）+ 单一 viewport composite（候选/已提交/Union 共用）+ Commit 后隐藏 | `b94382c` `be16a27` `0e22116` | **立项候选（站 1 显示面）** | 我方 maskOverlayStyle tint 交换语义近似（MaskToolbarView:136）；无候选态 live 预览样式。SwiftUI overlay 形态实现成本低（无需 Alcedo 的 QSG 专属通道重活） |
| B8 | SM9 工具面板（icon 工具面 + 三 prompt 工具 Point/Box/Path ≤64 点 + Add/Subtract + Click level + People 列表 + 五段开进度 + 单 Confirm） | `48d7e91` `9cfe688` `ec3ac37` | **立项候选（站 1 交互面）** | 我方 click/⌥-click/⇧-box 三手势已有；**Path 笔触（24px 间隔 ≤16 点采样）与 click level 缺**；Layer B addIncludedPoint 序列投喂等价 SAM 多点 |
| B9 | S3OD alpha 上采样（joint bilateral，guide 图引导，D23：20ms/换算 + 50ms/会话） | `1d41e79` `65339f7` | **注记（质量参考）** | 我方 Layer B 原生输出分辨率较高 + AIMaskResample 上采样已有；若 Sky/语义分割后边缘出阶梯，此法是现成药方 |
| B10 | SM2 模型下载面板（R2/HuggingFace + SHA-256 + 许可随附） | outline（SM9 后） | **不适用** | 零模型引入即零下载面；我方 Layer B DownloadableAssetsRequest 走 Apple 官方管道 |

### 主题 C：杂项（~28 commits）

| # | 上游交付 | 上游锚 | 判定 | 依据 |
|---|---|---|---|---|
| C1 | **color wheels LGG+Offset 语义修订**：归一化影调坐标（黑−6EV..白+6EV，t∈[0,1]）四轮各自支点 + Offset 整体；K 单位 EV；旧公式废弃（我方 M2-5 照抄的正是旧版） | `e1effd8` + `color_wheel_tonal_lgg_plan.md` | **立项候选（站 4 主件）** | 我方 `ColorWheels.metal` = 上游已废弃旧 CDL 公式（三支点全在可见范围外，Lift≈整体乘法）——**真 parity gap**；数学照 plan §3 重写 + offset 第四轮 + 旧档迁移（OQ-M9-7：process v3 双臂） |
| C2 | **filmstrip 跟随 Library 过滤器 + 磁贴 editing/selected 双态 + caption 两行（stars 右对齐 + 文件名）+ 被滤掉的打开图关闭** | `7ccb0ec` | **大部分已有** | 我方 FilmstripView 已跟 LibraryGridModel.rows 同过滤器游标 + selection ring + current accent；**差 stars on tiles**（站 4 小件）+ 双 token 细化 |
| C3 | LUT encodings 26→50 条（Canon Log 1/2/3×gamut、Cineon、REDLogFilm、F-Log2C、Apple Log 2、L-Log、KineLOG3、GP-Log2、LogC3 EI 阶）+ searchable picker | `eedc0c0` `0fa8548` | **立项候选（站 4）** | 我方 LutEncodingCatalog 16 条（M3-1 表驱动形态平移 +24）；picker 搜索框 |
| C4 | search palette（全局搜索对话框→⌘K palette + recent + filter rows）+ 语义搜索 folder scope + relevance 校准 | `6ee9fab` `1c21de7` `023a1d1` | **已有** | 我方 M7-2 MCP search_photos + SemanticEngine/EmbeddingScanner 已交付；palette UI 形态差异非功能缺口，注记 |
| C5 | LibRaw 并行 LJPEG DNG 解码 / Canon R50V·PowerShot V1 支持 / Adobe camera matrices 扩覆盖 / Lensfun 43f9e001 + Nikon Z 镜头名 | `ada6f00` `4258595` `8b17e2a` `c0d8dd4` | **不适用** | CIRAW 官方解码 + LENS-01 数据钉版自管 |
| C6 | macOS CI in-process 自动化测试 segfault 修复 / DuckDB 钉版 / QML 大写信号 handler / clang-tidy 命名 | `2f5431b` `c0427b9` `5790330` | 注记 | 上游工程卫生 |
| C7 | 编辑器 GPU 资源导出前释放 / sidecar 冷启动 UI 线程释放 / search palette settings drawer | `dab2473` `8d851f1` `c004d5c` | 注记 | Alcedo 自研 RHI/sidecar 结构缺陷修复，我方无同构面；「导出前释放编辑 GPU 资源」质量点观察（MetalContext clearCICaches 邻域） |

**增量节二总判定**：**立项候选 5**（B3 任务蒙版 / B5 会话形态 / B6 Expand / B7 显示 /
B8 交互 → 站 1；C1 色轮 → 站 4；C2 stars/C3 encodings → 站 4）；**路线豁免 2**（B1
模型集、B2 sidecar——Vision 原生替代）；**已有/不适用 5**；注记 3。正本 =
`M9-CHARTER-INPUT.md` §2.1/§2.4。
