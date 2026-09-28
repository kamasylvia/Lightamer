# Phase 14 VALIDATION — MCP Server

- **status: validated**
- **nyquist_compliant: true**
- **签核**: 2026-09-28（14-4 T4，executor subagent worker）
- **C 档第 3 停执行记录**: 夜间授权先例 **D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1 / 13-VALIDATION**——VALIDATION 结论落盘即签核，晨审可推翻（推翻即回滚 status 并回注修复批）。

## SC#1..7 三列证据

| SC | 判据 | 一手锚（源码/产物） | 测试锚 |
|---|---|---|---|
| **SC#1** | 工具集可用：load_image / apply_params / render_preview（分辨率/格式参数化）/ iop 清单与参数 schema 元数据 | `EditingToolset.swift`（5 工具）+ `IopCatalog.swift`（18 iop 手写表 + 反射守卫）+ `QuickLookRenderer.renderedPlane` 消费缝（14-2 可见性放开）；load_image 限会话成员（relPath 校验）；render_preview 默认 1024/q85 上限 2048/q90（`McpImageBudget`）| `McpEditingToolsetTests` 20/0 + `McpRenderParityTests` 9/0 + editing 域快照（McpRegistrySnapshotTests）；反射守卫 18/18（键集 = 编码 wire truth）| SC#3 端到端即本行字面（见下） |
| **SC#2** | 双入口：GUI 开关开启即启动/关闭即停；CLI 无头启动同一 server（无 GUI 进程）| `McpServerController`（startEmbeddedIfPreferenceEnabled / runHeadless 同一 makeRegistry 单内核）+ `SettingsView` MCP 节（`mcp_server_enabled` toggle 接 14-1 启停钩子，14-4 T1 落控件）+ `--mcp-stdio`/`--mcp-http` headless 分叉（LightamerEntryPoint，R3 关闭）| `McpHostTests` 18/0（stdio 子进程真实回包 + HTTP E2E）；`testHelloConformanceAcrossThreeHostForms`（stdio/HTTP/InMemory 三宿主同一核同元组）；GUI 截图零害（14-1 T1）| GUI toggle 实机点按 = Manual-Only（自动化腿 = SettingsView AX id `settings.mcp.enable`） |
| **SC#3** | 端到端：载入 DSC00012.ARW → ≥3 iop → 预览与本地渲染量化一致 | 同 sidecar 同参域：renderedPlane vs ExportRenderer.renderStage **plane maxDiff=0**；inline JPEG 与本地编码**逐字节等**（共享单次 CIRAW decode）| `testParityPlaneByteIdenticalToExportRenderStage` + `testParityInlineJPEGMatchesLocalEncodeOfGoldenPlane`（14-2）；SC#3 端到端 9/9：真 RAW 载入→GUI-live 插步硬拒→3 iop apply→render_preview 字节级一致→HTTP 宿主同缝字节一致（双宿主红线）| MCP-03 口径诚实条款：sRGB 编码域对齐、GUI EDR 显示域不对齐（README + 工具描述落位，14-4 T3） |
| **SC#4** | 安全面：默认仅回环；非回环必须带鉴权 token；文档明示风险 | `McpHTTPHost.loopbackHost = "127.0.0.1"` 硬编码常量（无设置可改）；`.lan` 分支 = 显式 toggle（`mcp_lan_exposure_enabled`）+ Bearer 强制 + 风险文案（`settings_mcp_lan_risk`）；SDK Origin/Host pipeline 未禁用 | `testHTTPEndToEndSDKClientRoundTrip`（运行时 loopback 绑定实证）+ `testLANExposureRequiresBearerToken`（401/401/200）+ `testOriginAndHostValidationPipeline`（403/无端口 403/Host 421/无 Origin 放行）+ `testBearerTokenGenerateAndConstantTimeCompare`；**安全走查五条全绿**（SUMMARY §安全走查）| 非回环实机局域网验证 = Manual-Only（单机环境） |
| **SC#5** | 筛选端到端：列照片（EXIF/rating/flag 索引查询）→ 批量缩略/联系表/ROI 细裁 → 写回星级/旗标/色标（sidecar 真 + GUI 同步可见），全程不碰像素与文件删除 | `CullingToolset.swift`（14 工具）+ `PhotoProjection.swift`（25 列投影 + keyset 游标）+ MetadataService 单源三段管线（GUI/MCP 同汇点）+ `McpImageBudget` 上限表 | `McpCullingToolsetTests` 27/0 + `McpCullingImageBudgetTests` 6/0：写回三断言 parity（sidecar 字节 + lindex 行 + query face）、批量三段回归、live-target claim 不动负例、MCP-08 封闭集证明（无删除/移动/像素工具）、预算对账（缩略 16.3KB/3、联系表 18.6KB）| inspector 行不跟随属预期（R7 处置，14-3 登记关闭） |
| **SC#6** | culling 方法论支撑：burst 分组 + 脸部区域定位可组合筛片流 | `list_bursts`（2.0s + camera_model 聚类 + StableHash decimal id）+ `get_face_regions`（VNDetectFaceLandmarksRequest 直发 + 像素框换算）| 聚类 golden + 2.0s 含边界补钉（`testBurstGapExactlyAtThresholdStays`，14-4）+ 换算逐值 + 空数组=无脸（真 Vision 跑）+ landmark 补测（8 张真人像，精化增量 ≤0，R5 关闭）| 「全图阵列 → 相似组联系表 → 脸部细节」组合流 = SC#5 工具面 + agent 编排（SC#7 链演示 list→thumbs→rate） |
| **SC#7** | GUI launcher 端到端：偏好模板 → 一键拉起 agent → 挂自身 server → 写回落 sidecar + GUI stale 再生同步可见 → 日志面板显示 agent 文字流；外部直连与 launcher 双入口并存 | `McpLauncher.swift`（模板占位符 `{{LIGHTAMER_MCP}}`/`{{PROMPT}}` 单引号包裹 + `/bin/zsh -c` + 串行门 + SIGTERM→5s→SIGKILL 只及在册自家 pid）+ `McpLauncherPanelView.swift`（环形缓冲 2000/暂停滚动/复制/写回计数诚实面）+ `McpServerController.embeddedWriteCallCount`（requiresWriter 调用计数缝）| `McpLauncherTests` 10/0（占位符逐字 + zsh 元字符转义往返 + 串行拒绝 + launch-failed 槽位释放 + 退出码面 + 探针退役）+ `McpLauncherSentinelTests` 9/0（注入逐字端到端 + 串行哨兵 + 终止只及自家〔在册表负例：外来 pid 拒绝且不动〕+ TERM 顽抗子 SIGKILL 兜底 + 2000 行裁头 + 复制/跟随语义）+ **`testSC7LauncherChainEndToEndWithDualEntry`**（真子进程 curl agent：发现端点 → initialize → list_photos → get_thumbnails stale:true〔真 tier-B 缓存图〕→ set_rating 落 sidecar+lindex → 日志环捕获 AGENT-DONE → stop 面 .notRunning；直连 SDK client 先在且观察 agent 写回 = 双入口并存）| 一键真机点按观感 + 真实外部 agent（pi/omp）端到端 = Manual-Only（自动化腿：curl 哨兵 agent 即真实 agent 形态——Streamable HTTP + JSON-RPC） |

## 覆盖矩阵

| 需求 | 状态 | 交付 plan | 备注 |
|---|---|---|---|
| MCP-01 | Delivered | 14-1（底座）+ 14-2（修图面） | 5 工具 + IopCatalog 反射守卫 |
| MCP-02 | Delivered | 14-1（双宿主）+ 14-4（GUI toggle 控件） | stdio/HTTP/InMemory 三形态一致性 |
| MCP-03 | Delivered | 14-2 | parity 双层字节级（R6 关闭未触发划界重谈）|
| MCP-04 | Delivered | 14-1（valve/Origin）+ 14-4（LAN toggle + 风险文案 + 走查）| 安全走查五条入 SUMMARY |
| MCP-05 | Delivered | 14-3 | 25 列投影 + 图像三件套 + 预算表 |
| MCP-06 | Delivered | 14-3（写五件）+ 14-2（SC#5 GUI 联动段） | MetadataService 单源 + stale 再生联动 |
| MCP-07 | Delivered | 14-3 | burst 聚类 + Vision 脸框（R5 关闭）|
| MCP-08 | Delivered | 14-3（封闭集证明）+ 14-4（白名单负例 + 快照冻结）| 第 20 工具 negative 落 McpFinalSnapshotTests |
| MCP-09 | Delivered | 14-2（export_image）+ 14-3（preset 三件 + set_keywords）；研究项 A = flock 单写者 + GUI-live 判据（14-1/14-2）；B = v1 history append 语义、版本面 defer v2（§RQ-14-15①复核通过）；C = match_color 零占用（14-4 白名单负例钉死）| |
| MCP-10 | Delivered | 14-4 | 模板/占位符/串行/终止/日志面板/写回计数；app 零 AI 代码 |
| 登记批：union 装配（culling 14 工具接宿主）+ McpImageBudget 统一消费位 | Delivered | 14-4 T1 | 14-3 遗留两条兑现 |

**研究项收口**：A 关闭（单写者机制五态实测 + 只读降级 + GUI-live 判据）；B 关闭-维持 v1（复核通过留痕）；C 关闭-零占用（白名单负例）。**R1..R9 全关闭**（R3 headless 分叉可行零回退；R6 parity 字节级）。

## Manual-Only 汇总（verify-work 用户终验清单）

**pending-manual（自动化腿全部在案）**：
1. GUI Settings toggle + 模板/提示词填写观感（`settings.mcp.*` AX id 在案）
2. Launcher 面板一键真机点按（启动/停止/跟随滚动/复制按钮，`mcp.launcher.*` AX id 在案）
3. 真实外部 agent（pi/omp 配 Streamable HTTP 端点）跑一轮真筛图流（自动化腿 = curl 哨兵 agent 全链绿）
4. 非回环暴露实机局域网验证（单机环境；自动化腿 = testLANExposureRequiresBearerToken）
5. zh/en 界面文案实机切换观感（L025 smoke 数字 = 全 suite String Catalog smoke，zh 键 1146）

## 缺陷处置记录

1. **list_photos 游标两缺陷（重，14-3 独立验收抓出）**——值类谓词缺 NULL 尾桥 + scanEpoch 载荷恒 .null。修复 = test-first fix 提交（14-3 验收轮）。闭环。
2. **探针 toolset 退役波及面（14-4 T1 预期内）**——McpHostTests/McpRegistrySnapshotTests/ParityTests 的 probe 依赖改写为封闭面断言；hello 一致性 canonical call 换 list_iops。闭环。
3. **SC#7 链测试 SSE data 行空载荷（14-4 T3 执行期）**——初版解析器对空 `data:` 行抛 JSON 错误且被任务取消语义掩盖（表现为 CancellationError）。修复 = 宽容解析（跳空行 + 失败回退原文）+ 根因修复（filter value wire 形状 `{kind,value}` 修正 + tier-B 缓存图 fixture）。闭环。
4. **get_face_regions 超时档偏紧（14-3 验收注记）**——10s list 档对 RAW 解码腿不足；14-4 移至 20s 图像档。闭环。
5. **burst 2.0s 含边界未钉（14-3 验收注记）**——补 `testBurstGapExactlyAtThresholdStays`。闭环。

## 终轮回归

**1881 执行 / 11 skip / 0 fail（780.3s，EXIT=0；私有日志 /tmp/la-144-final.log）**——基线 1857（14-2 验收修复后终值）→ +24：McpLauncherTests 10 + McpLauncherSentinelTests 9 + 写回计数测试 1 + McpFinalSnapshotTests 6 − probe 域净退役 2。在案 flake（LayerE2E / ToneEqual / QuickLook 计时类）本轮未现身。

## 签核判定

**Phase 14 签核：PASS（SC#1-7 ✅；status: validated + nyquist_compliant: true；终轮 1881/11skip/0fail；MCP-01..10 全 Delivered；Manual-Only 5 行全部登记且自动化腿在案，不阻塞签核；C 档第 3 停按夜间授权先例执行，晨审可推翻）。**

*Phase 14 — MCP Server 四 plan（14-1/14-2/14-3/14-4）全闭环。*
