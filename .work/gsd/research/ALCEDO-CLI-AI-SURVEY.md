# Alcedo CLI + AI 功能面侦察（ALCEDO-CLI-AI-SURVEY）

> **日期**: 2026-10-16（用户指令：「Alcedo 更新了其 cli 和 AI 功能，我们的 cli 和 AI 也照抄」）
> **来源仓库**: `/Volumes/UNITEK/Documents/Development/AlcedoStudio`，HEAD `6024386`（v0.3.3+2，2026-10-16 ff）
> **性质**: GPL-3.0 只读侦察——功能面 1:1 盘点 + 我方 gap map + charter 切分建议。**代码零复制**；功能行为克隆合法（见 §6 许可边界）。
> **关联正本**: `ALCEDO-FEATURE-MAP.md`（2026-09-27 产品面测绘，本文件是它的 CLI/AI/automation 增量专卷）；自动化上游计划原文 = Alcedo 仓 `docs/roadmap/alcedo_studio/automation/cli_mcp_automation_plan.md`（3365 行，AU1..AU16，下称「AU 计划」）。

---

## 0. 结论摘要（供 charter 直接消费）

- **Alcedo CLI 面** = 「thin CLI + 常驻会话宿主」架构：`alcedo-cli` 独立小二进制（只链 AutomationProtocol+Qt Core/Network），经 JSON-RPC 2.0 over 本地 socket 驱动常驻的 `alcedo_main`（GUI 或 `--headless`）会话。**10 个 CLI 动词 + 48 个宿主命令 + 5 条通知 + 5 档退出码**（§1）。
- **Alcedo AI 面** = 三层：①`alcedo_mind` Rust gRPC sidecar（**5 服务 / 26 RPC**：CLIP 嵌入 + 远程 LLM 图像分析 + 凭据 + 模型管理）；②C++ app 服务层（语义检索/自动打标/AI 描述/AI 评分/FTS/凭据仓/模型下载）；③编辑器内置模型推理（DemosaicNet 神经去马赛克）。**AI 分析命令被明确排除在 CLI/自动化面外**（付费调用 out of scope，AU 计划 §1.2/§1.3）——CLI 是「操作面」，AI 是「产品内功能」，两者在 Alcedo 也是分离的（§2）。
- **MCP**：Alcedo **未实现**（AU15 planned，`alcedo-cli mcp` stdio MCP server 只存在于计划）；我方 **MCP server 已实现**（20 工具封闭集 + launcher + stdio/HTTP 双宿主）——**编排面我方反向领先**，这是本轮最大意外（§3.3）。
- **Gap 计数**：CLI/编排面逐项对照 27 行——已有/等价 12、缺 13（其中 2 项 by-design 不抄：任意路径导入/删除）、可选 2；AI 面对照 15 行——已有/超集 13、缺 2（其一 by-design 不追）。真正值得抄的缺口集中在：**MCP 工具 additive 补齐（搜索/对比预览/版本只读/history 只读/跨图调色复制）+ GUI agent 控制权（turn-taking）+ commit attribution + agent 操作 skill 文档**（§4/§5）。
- **AI 面结论**：我方 M2-10 五件套（检索/打标/描述/评分/worker）已对齐或超集 Alcedo AI 产品面；AI 面「照抄」的实际工作量≈0，charter 焦点应全放在编排面与 CLI 面（§5）。

---

## 1. Alcedo CLI 面全量盘点

### 1.1 架构形态：thin CLI + 常驻会话宿主（headless 宿主形态）

```
alcedo-cli (独立进程, ~1000 行, 只链 AutomationProtocol + Qt6 Core/Network)
   │  每次调用 = 短命进程；读会话文件发现 socket → 连接 → 发一条命令 → 打印 → 退出
   ▼
JSON-RPC 2.0 over QLocalSocket（Unix domain socket / Windows named pipe）
   │  一行一个 JSON 对象；行上限 16 MiB；请求恒带 id；错误码 = JSON-RPC 标准段 + 自定义段
   ▼
alcedo_main (常驻会话宿主——同一 GUI 二进制的两种形态)
   ├─ GUI 宿主：正常窗口进程内嵌 AutomationServer；agent 与用户共享一个应用会话
   └─ headless 宿主：`alcedo_main --headless`，无窗口无 QML；CI 与无人值守 agent 用
```

证据：
- CLI 目标定义：`alcedo_studio/src/ui/alcedo_cli/CMakeLists.txt:1-4`（"console client for automation sessions. It links only the automation protocol and Qt, never the album backend, so that it starts fast and stays small"）。
- CLI 入口：`alcedo_studio/src/ui/alcedo_cli/main.cpp:11-20`（与 alcedo_main 同 org/app 名，使 AppLocalDataLocation 落同一目录）；命令分派 `cli_commands.cpp:923-972`。
- 协议常量：`alcedo_studio/src/include/automation/automation_protocol.hpp:18-21`（`kAutomationProtocolVersion = 1`；`kMaxAutomationLineBytes = 16 MiB`）。
- 服务器：`alcedo_studio/src/include/ui/alcedo_main/automation/automation_server.hpp:20-30`（QLocalServer；**接受多连接**，每连接独立读缓冲、各自收响应；**通知广播给所有连接**；server 与全部 handler 跑在拥有 server 的线程 = **GUI 线程**——线程锁定即序列化，天然单写者）。
- headless 宿主：`alcedo_studio/src/include/ui/alcedo_main/automation/headless_host.hpp:18-27,40-57`（`--project <path>` / `--create <folder> <name>` / `--session` / `--session-dir` / `--editor-backend cuda|opencl|metal` / `--viewport WxH`（默认 1920x1080）/ `--settings-dir` / `--log-file`；退出码 0=成功/2=usage/3=后端启动失败/4=项目打开失败/5=自动化 server 或会话文件启动失败/6=Exiv2 XMP 初始化失败）。

**与 GUI 的关系**：不是「GUI 内嵌 CLI」也不是「独立重实现」——CLI 与 QML 面板调**同一个 C++ owner 操作**（AU 计划 §1.2 "QML and automation call one C++ operation"），GUI 宿主 = 同进程内嵌 server，headless 宿主 = 同二进制换启动参数。`session start` 在 CLI 安装目录旁找 `alcedo_main`（macOS bundle `<Bundle>.app/Contents/MacOS/`，Windows `bin\`；`cli_commands.cpp:458-477`，可 `--host-binary` 覆盖）。

### 1.2 会话发现 / 锁 / 并发纪律

- **会话文件**（发现协议）：`<AppLocalDataLocation>/automation/sessions/<name>.json`，字段 = `protocol_version / session_name / socket_name / pid / host_mode("headless"|"gui") / project_path / started_at`；宿主 listen 后原子写、shutdown 删除（`alcedo_studio/src/include/automation/automation_session_file.hpp:15-29,41-60`）。会话名字符集白名单 `[A-Za-z0-9._-]`。
- **会话选择**：`--session <name>` → 环境变量 `ALCEDO_SESSION` → 恰有一个活会话时自动选它；多个活会话报错列出名单（`cli_commands.cpp:214-264`）。活判定 = 文件可读 + 协议版本匹配 + pid 存活 + socket 答 `session.ping`（:177-203）。
- **并发纪律（单写者）**：
  - 协议层：多客户端连接允许；全部 handler GUI 线程序列化执行（§1.1）。
  - 状态变更命令需 **agent control**（GUI 宿主）：`control.acquire`（带 `holder_name`）→ 才能跑 `changes_state=true` 的命令；无 control = `-32003 control_not_held`；用户夺回后 agent 再 acquire = `-32004 control_revoked_by_user`，直到用户从 UI「Return control」。headless 宿主 agent 恒持有（null owner → `held: true`）（`automation_control_commands.hpp:15-27`；错误码 `automation_protocol.hpp:24-37`：-32001 not_ready / -32002 rejected / -32003 / -32004 / -32005 busy / -32006 timeout / -32007 failed）。
  - **GUI 宿主 turn-taking 语义**（AU 计划 §2.8）：agent 持锁期间 UI 禁编辑动作（调整面板/编辑工具/undo/redo/history 头移动/版本变更/换图/导入/删除/评分/导出/项目开关），保留浏览/缩放/搜索/设置；agent 控制走既有后台任务通道（task island 展开显示 "Agent · claude-code · editor.set saturation 20"，点击看状态，**Cancel = Take control**）；后续 `7e0c9cb` 迭代为 **Stop 语义**（agent 任务钉住 + 逐命令 activity 记录 + Stop 后同 agent re-acquire 可恢复任务）。
  - headless 宿主内：`library.selection.*` 不可用（返回 `not_ready`）——GUI 选区概念仅 GUI 宿主有效（AU 计划 §2.6 表注）。
- **会话生命周期命令**：`session start --headless`（拉起 detached 宿主、轮询会话文件+ping 直到就绪、失败回读 stderr tail；`cli_commands.cpp:550-669`）；`session stop`（`session.shutdown` + 等进程退出 60s）；`session list`；`session prune`（只删 stale 的 Alcedo 会话记录文件，读不了/非 Alcedo 文件一律保留并报告——`c1a66b4`）。Windows 侧 `HostHandleList` 限制子进程继承句柄、Unix 侧 `CloseFileDescriptors`——防调用方管道被宿主继承导致 EOF 不来（`cli_commands.cpp:384-456,610-615`，issue #354）。

### 1.3 CLI 动词全量（10 个）

| 动词 | 参数 | 输出 |
| --- | --- | --- |
| `call <method> [<params-json>]` | 任意宿主命令 + JSON 对象参数 | 默认缩进 JSON；`--json` = Compact JSON（`cli_commands.cpp:322-339,266-291`） |
| `batch` | stdin 每行一个 `{"method":...,"params":{...}}` | 单连接顺序发送；每请求输出一行 compact JSON（`id`=请求 id 或行号 + `result`/`error`）；任何行错 = 退出码 1（:837-919；contact-sheet 批量缩略用例 = `6a0fe59`） |
| `schema` | — | `session.describe` 的 `commands` 数组（method + `(changes state)` 标记 + description），或 `--json` 全量（:341-368） |
| `session start --headless` | `--project <path>` 或 `--create <folder>,<name>` 必选；`--editor-backend cuda\|opencl\|metal` / `--viewport WxH` / `--settings-dir` / `--log-file` / `--host-binary` | 就绪后打印 session/pid/project（JSON 模式含 socket 路径）；超时/早退报 stderr tail（:550-669） |
| `session stop` | — | `session.shutdown` + 等待进程退出（:671-718） |
| `session list` | — | 全部会话文件 + 状态（`live`/`stale`/`unsupported-protocol`/`unreadable`）（:730-769） |
| `session prune` | — | 移除仅 stale 的 Alcedo 会话记录；其余文件 skipped+reason（:771-803） |
| `watch` | — | 持续打印通知行直到中断（:805-835） |
| `version` / `--version` | — | Alcedo Studio 版本号（`ace755e`） |
| `help` / `--help` / `-h` | — | usage 文本 |

全局选项（任意位置可放）：`--session <name>`（或 `ALCEDO_SESSION`）/ `--session-dir <dir>` / `--json` / `--timeout <ms>`（注入每命令 `timeout_ms` 参数；缺省 120000）（`cli_commands.cpp:61-89,128-175,303-306`）。

**退出码**（`cli_commands.hpp:11-17`）：`0` 成功 / `1` 命令错误（JSON-RPC error）/ `2` 会话选择错误 / `3` 连接错误 / `4` usage 错误。

### 1.4 宿主命令族全量（48 个 JSON-RPC method + 5 条通知）

> 参数/结果摘自 AU 计划 §2.6 命令目录 v1 与命令实现源码；全部命令接受 `timeout_ms`。编辑器参数一律 **UI 单位**（面板显示值，如 saturation -100..100）。

**会话与状态（4）**
| method | 参数 → 结果 |
| --- | --- |
| `session.ping` | → `{pong:true}` |
| `session.describe` | → 协议版本 + host 信息 + **命令 schema 全表**（`changes_state` 标记；机器可读自描述——`automation_json_schema` JSON Schema 子集校验） |
| `session.shutdown` | `persist`(默认 true) → 优雅关停 |
| `state.get` | → project / workspace / editor 状态 + control 状态 + 运行中任务（统一状态快照） |

**控制权（3）**：`control.acquire(holder_name)` / `control.release` / `control.get` → control 状态（`held`/`revoked_by_user`/`holder_name`）。

**项目（4）**：`project.create(folder,name)` / `project.open(path)` / `project.save` / `project.close(persist)`。

**图库（10）**
| method | 参数 → 结果 |
| --- | --- |
| `library.import` | `paths[]` 或 `folder`+`recursive` → `task_id` |
| `library.folders` | → 文件夹树 |
| `library.list` | `folder_id`/`offset`/`limit`/`sort` → 条目（element_id/image_id/文件名/评分） |
| `library.thumbnail` | `element_id`/`out`/`long_edge` → PNG 路径（**输出路径不存在才创建**——`1f12551` 防覆盖） |
| `library.thumbnails` | 批量 ≤**1000** 张 → `<element_id>.png` + 逐张失败项（contact sheet 用例，`6a0fe59`） |
| `library.info` | `element_id` → 导入时读到的源文件与拍摄值（缺值省略；photo info，`6a0fe59`） |
| `library.selection.get/set` | GUI 宿主专用（headless `not_ready`） |
| `library.rate` | `element_ids[]`+`rating 0..5` → task_id 或计数 |
| `library.delete` | `element_ids[]`+`scope(project\|album)` → 删除 id |

**编辑器（10）**：`editor.open(element_id,image_id)` / `editor.close(persist)` / **`editor.catalog`**（→ 全参数目录 UI 单位——AU7..AU9 建成：标量/Tone/Look/Post + RAW 解码 + 输入 profile + 镜头 + 裁剪 + 显示变换 + WB + HLS + 色轮 + 曲线 + LUT） / `editor.get(fields[])` / `editor.set(field,value,note)`（→ 新 head commit + 值；**note 进 commit**） / `editor.batch_set(changes[],note)` / `editor.undo`/`editor.redo` / `editor.history`（→ commits **含 author 与 note**） / `editor.actions`（→ EditorActionPolicy 可用性）。字段归属解析到 owner 节点（`822ae9e`）；`e35bd78` 保证渲染失败也答 editor 命令；`daf1948` lut/input_profile 读值可写回。

**版本（6）**：`versions.list/create(name)/branch(name,from_commit)/checkout(version_id)/rename/remove`——Mini-Git 版本树 + **commit attribution**（每 commit 有 author，默认 user，agent commit 存 `agent` + 可选 note；Versions/History 面板显示作者）。

**渲染/导出/搜索/LUT（6）**
| method | 参数 → 结果 |
| --- | --- |
| `render.preview` | `out_dir`/`long_edge`/`region`/**`compare`(none\|root，默认 root——原图对比出图)**/`file_stem` → PNG 路径 + 像素尺寸（`current`，compare:root 时加 `root`） |
| `export.options` | → 默认值/格式/位深/限制（导出选项自描述） |
| `export.run` | `targets[]`/`out_dir`/options → `task_id`（FAIL 策略一步内拒绝覆盖既有文件——`6203791`） |
| `export.status` | → 队列行 + 计数 |
| `search.query` | `text`/`offset`/`limit`/`mode(auto\|fuzzy)` → 匹配 + 分页 |
| `lut.list` | → LUT 库清单（`d87e4b3`） |

**调色复制（3）**：`adjustments.items` / `adjustments.copy` / `adjustments.paste`——批量编辑用；paste 给每张图建一个 Version + 一个 agent commit；编辑器打开中的图走 editor session，其余走后台任务、完成态列每图结果（`e75cf2a`；目标 Grade 默认值保留语义 `9f9fc5e`）。

**任务（2）**：`tasks.list` / `tasks.wait(task_id 或 idle:true)` → 终态（后台任务面：导入/评分/导出/paste 等长操作经 task tracker）。

**通知（host→client 广播，5）**：`session.state_changed`（editor 会话状态/element_id/image_id）、`history.changed`（element_id/image_id/head_commit/version_id）、`task.updated` / `task.finished`（任务 id/kind/进度/终态/计数/错误摘要）、`control.changed`（held/revoked_by_user/holder_name）（AU 计划 §2.5）。

**明确排除在命令面外**（AU 计划 §1.3）：图像分析（describe/score）、语义生成、模型下载命令（付费 AI 调用 out of scope）；LUT 包管理/更新安装/应用设置；蒙版 authoring、节点图编辑、对比视图、Paste/Merge（协议设计允许日后 additive）；「照片审美 taste」skill 不做，只做操作 skill。

### 1.5 输出机器可读性

- 默认 = 人读（缩进 JSON / 制表符表 / 短句）；`--json` = compact JSON 单行。
- `batch` = JSONL 请求-响应流（一行进一行出）。
- `session.describe` = 命令 schema 自描述（JSON Schema 子集：类型/枚举/`maxItems` 等——`74a2123` boolean 枚举规范形、`6a0fe59` maxItems）。
- 参考文档机器同步：`scripts/automation/generate_cli_reference.py` 从 schema 生成 CLI reference（`2b943fa`），发布于外部仓 [alcedo-skills](https://github.com/zidage/alcedo-skills)（`5846be6` README 链接替代 submodule）——**agent 操作 skill 与 CLI 参考独立成仓**。

### 1.6 Roadmap 状态（AU 计划）

- **AU1..AU14 = implemented**（协议/CLI/headless 宿主/项目/图库+任务+CI/选择评分删除/参数目录三波/editor+render/versions+attribution/export/search/GUI server+agent control），**AU15 = planned**（`alcedo-cli mcp` stdio MCP server：工具列表来自 `session.describe`、`editor.set`→`editor_set` 点换下划线、`render.preview`/`library.thumbnail` 结果内嵌 MCP image content、MCP 工具含 `session_start/stop`、`.agents/skills/alcedo-automation/SKILL.md` 操作 skill、安装规则）、**AU16 = planned**（操作序列鲁棒性/恢复测试）。
- 已知未决：GUI automation server 默认开（`automation/serverEnabled` key，Settings 开关未建）；`alcedo-cli mcp` 全部未写码（全仓 grep `Model Context Protocol`/MCP server 实现零命中——仅 memcpy 误报）。

---

## 2. Alcedo AI 面全量盘点

### 2.1 总体形态：独立 gRPC sidecar + app 服务层 + 编辑器内置推理

```
alcedo_main (C++/Qt app)
  │  gRPC (tonic, protobuf) — 独立子进程生命周期由 AiSidecarRuntimeService 管理
  ▼
alcedo_mind (rust/puerh_mind — 独立 Rust 二进制; ort ONNX Runtime + CoreML/DirectML)
  ├─ SemanticService      — 本地 CLIP 嵌入（MobileCLIP ONNX; plhery/mobileclip2-onnx:s2）
  ├─ ImageAnalysisService — 远程 LLM 图像分析（describe/score/analyze/batch）
  ├─ AiRuntimeService     — 能力列举 / 凭据注册吊销 / 任务取消
  ├─ ModelManagerService  — 本地模型 profile 清单/校验/删除
  └─ HealthService        — ping/version
```

- sidecar 进程编排：`alcedo_studio/src/include/app/ai_sidecar_runtime_service.hpp`（`AiSidecarRuntimeOptions`：runtime_binary/model_root/provider_config_dir/host 127.0.0.1/port 0（动态）/model_id 默认 `plhery/mobileclip2-onnx:s2`/hf_endpoint 默认 `https://hf-mirror.com`/device auto/batch_cap 512/batch_wait 25ms/`allow_download=false`/startup_timeout 5s；状态机 stopped/starting/ready/stopping/failed + issue 枚举 binary_missing/start_failed/readiness_timeout/runtime_exited…；`StartAndWaitInteractive` 泵 UI 事件循环保冷启动响应性 + 可取消）。
- C++ 客户端门面：`alcedo_studio/src/sidecar_client/`（`Client` = runtime/credentials/models/semantic/image_analysis 五个子客户端接口，`client.hpp`）。

### 2.2 gRPC 服务面（5 服务 / 26 RPC）

| 服务（proto） | RPC | 功能 |
| --- | --- | --- |
| `HealthService`（common.proto:5） | `Ping` / `GetVersion`（2） | 健康检查 |
| `SemanticService`（semantic.proto:7） | `Ping` / `EmbedText` / `EmbedImage` / `EmbedTextBatch` / `EmbedImageBatch` + 同五 **V2 变体** + `GetModelInfo` / `GetRuntimeStatus`（11） | 本地 CLIP 文/图塔嵌入（内部自动批处理；512 维归一化向量；256px 输入；V2 = 演进 wire 形） |
| `ImageAnalysisService`（image_analysis.proto:37） | `DescribeImage` / `ScoreImage` / `AnalyzeImage`(describe+score 合一) / `BatchAnalyzeImage` / `ListModels`（5） | 远程 LLM 分析：caption/tags/scene/confidence + 1..5 星评分 + 用量元数据 + rendition 元数据 |
| `AiRuntimeService`（ai_runtime.proto:18） | `ListCapabilities` / `RegisterCredential` / `RevokeCredential` / `CancelTask`（4） | provider 能力表 / API key 经 TTL handle 注入 sidecar / 推理任务取消 |
| `ModelManagerService`（semantic.proto:24） | `ListModelProfiles` / `ListInstalledModels` / `ValidateModel` / `DeleteModel`（4） | 本地 CLIP 模型资产生命周期 |

### 2.3 远程 LLM provider 生态（5 个适配器，全 HTTPS-only rustls）

`rust/puerh_mind/src/service/providers/`：
- `openai_chat_compatible.rs` — OpenAI 兼容 `/chat/completions`（覆盖 openrouter 类生态）
- `anthropic_messages.rs` — Anthropic `/v1/messages`
- `openrouter.rs` — OpenRouter 专项
- `volcengine_ark.rs` — 火山方舟专项
- `openai_codex_oauth/` — OpenAI Codex OAuth 流

provider 配置目录 `rust/puerh_mind/configs/providers/`（8 个 JSON：ccswitch_anthropic/ccswitch_openai/opencode_go_*/openrouter/volcengine_ark* 等——「灵感来自 ccswitch」的多 profile 切换）；prompt 配置 `configs/prompts/image_analysis_system_prompts.json`。速率限制/5xx 重试/取消/超时在 provider driver 层（wiremock 测试在案）。凭据存储 = **OS 级**：Windows Credential Manager / macOS Keychain（`alcedo_studio/src/include/app/ai_credential_store.hpp:53-86`），经 sidecar `RegisterCredential` TTL handle 注入（真值不落 app 配置）。

### 2.4 App 服务层 AI 功能清单（8 项）

| # | 功能 | 证据 | 交互形态 |
| --- | --- | --- | --- |
| A1 | **导入期自动打标（语义生成）** | `app/semantic_generation_service.hpp`（SemanticGenerationItem 状态机 pending→thumbnail_ready→embedding_requested→embedded/skipped/canceled/error；结果含 label/second_label/margin/confident）；导入完成后 `SemanticGenerationDialog`「Use AI to analyze image content?」+ Remember My Choice + 后台运行 | 后台批量；进度弹层 |
| A2 | **CLIP 自然语言搜索** | `app/search_query_classifier.hpp:14-44`（四路由 Empty/Traditional/Label/Semantic——只有 Semantic 起 semantic runtime；token 预算 64 兜底）；`SleeveFilterService::SemanticSearchProvider` 接口 | GlobalSearchDialog 三段搜索之一 |
| A3 | **AI 描述（caption/tags/scene）** | `include/ai/ai_description.hpp:12-46`（file_id 键 + task_id/provider_id/model_id/prompt_profile_id/rendition_kind + active-for-search 标志）；远程 LLM，后台分析 | Inspector 面板展示 + 全文搜索索引 |
| A4 | **AI 评分（1..5 星 + 理由）** | `include/ai/ai_rating.hpp:12-60`（rubric_id/rubric_version 防口径漂移；1..5 契约 + NormalizeRating；Phase 7a **reasons-only 门**——产品星级走 EXIF Rating 字段，AI 行只存理由） | 设定严格度/输出语言；写回星级 |
| A5 | **AI 理解全文检索** | `storage/store/ai/ai_store.hpp:70-100+`（DuckDB 表 `(file_id,task_id)` 主键 upsert + 派生 `AiImageSearchText`/`AiImageFtsDocument` + **BM25 FTS 索引** best-effort，无 fts 扩展时退化为折叠文本匹配） | search 第三段 |
| A6 | **模型资产下载/管理** | `app/model_download_service.cpp` + `model_asset_catalog.cpp`；sidecar 侧 `hf-mirror` 三源、`allow_download=false` 缺省 | Settings「Local Content Recognition」页选模型（4 个模型文案见 FEATURE-MAP §8） |
| A7 | **provider profile 管理** | `app/ai_provider_profile.hpp:22-138`（多 profile、structured_output_mode=tool/strict、唯一显示名、sidecar config 目录投影） | Settings「Advanced Content Analysis」页 |
| A8 | **AI 侧车生命周期 UI** | `AiSidecarRuntimeService` Q_PROPERTY(state/issue/statusMessage/endpoint) | 状态可见 + 冷启动可取消 |

### 2.5 编辑器内置模型推理（非图库面）

- **DemosaicNet 神经去马赛克**：`alcedo_studio/src/decoders/processor/nn/`（`demosaicnet_bayer.cu` / `demosaicnet_xtrans.cu`（CUDA）/ `opencl_demosaicnet_tiled.cpp` / `metal_demosaicnet_cache.mm`（Metal 缓存）/ `demosaicnet_cache.cpp` / `demosaicnet_profiler.cpp`）——X-Trans 默认走它（FEATURE-MAP §2.5：`demosaic_method = default` 时 Bayer=RCD、X-Trans=Neural Engine）。**蒸馏神经去马赛克 = Alcedo 的「AI 在 RAW 域」主战场**。
- `src/nn/safetensors.cpp` — safetensors 权重加载器（256MiB header / 4GiB data 帽）。
- 我方定位：**架构性不追**——Lightamer 走 CIRAW（macOS 27 Neural Engine demosaic+denoise），demosaic 算法菜单不可达已入对标排除（PROJECT.md Constraints / STACK.md Decoder 策略）。

### 2.6 AI 与 CLI/agent 编排的关系（关键判读）

1. **AI 分析不在自动化命令面**（AU 计划 §1.2「Paid AI calls: Out of scope. Analysis commands are excluded」+ §1.3 排除清单）——CLI/MCP 驱动不了 describe/rate/打标；这些是产品内功能（GUI 触发 + 后台任务）。
2. **agent 消费 AI 的方式 = 消费其产出**：`search.query` 命中 AI 理解的 FTS/标签（检索面），`library.list` 读 rating（评分已落 EXIF 字段）——AI 是命令面的**数据源**而非**命令**。
3. **agent 自身智能 = 外部**（Claude Code 等 shell agent）：Alcedo 无内置 agent 运行时；`alcedo-skills` 外部仓提供操作 skill（如何开车，不含 taste）；GUI 宿主 turn-taking + task island 是「人与 agent 共驾」的全部 UI 面。
4. **「AI 客户端编排」vs「内置模型推理」判别**：
   - 客户端编排（外部 LLM + 本工具面）：CLI 全部 48 命令的预期驾驶者 = 外部 agent；AI 分析 = 远程 API 客户端。
   - 内置推理：CLIP（检索/打标）、DemosaicNet（RAW 域）——本地模型、无对话。

---

## 3. 我方现状对照（gap map 的「已有」侧基线）

### 3.1 MCP server（Phase 14 交付 + M6-5 收口，全在产）

- **形态**（`App/Sources/Lightamer/MCP/`）：一份 server 内核（`McpToolRegistry.swift` 纯 Swift 零 import MCP）× 两种宿主（GUI 内嵌 Streamable HTTP @127.0.0.1 + 无头 fork `--mcp-stdio`/`--mcp-http` 同 binary 分叉）+ 端点发现文件（port/token 指纹/pid/host/health）+ Bearer 校验（`McpBearerValidator.swift`）+ 会话帽 4。
- **工具面 = 20 工具封闭集**（14-4 冻结 19 + M6-5 match_color → 20；`71dbd371` 头注更新）：Editing 6（`load_image`/`list_iops`/`apply_params`/`render_preview`(分辨率/格式参数化，1024/q85 默认 2048/q90 上限)/`export_image`/IopCatalog 18-iop 元数据）、Culling 14（`list_photos`(25 列投影+keyset 游标)/`list_presets`/`apply_preset`/`diff_presets`/`get_thumbnails`/`get_contact_sheet`/`get_detail_crop`/`list_bursts`/`get_face_regions` + 星级/旗标/色标/备注/关键词写回）、MatchColor 1（`match_color` 参考图色彩匹配）。tools/list 快照测试钉死工具面（新增必须显式改快照）；错误码封闭表（`McpToolError` 15 档）。
- **并发纪律**：GUI 进程恒单写者（SidecarStore per-image actor + GUI-live 图写 typed error + server 单实例端点锁）；无 turn-taking control 概念（无 GUI 会话内 agent/user 控制权切换 UI）。
- **launcher（MCP-10）= 已实现**（14-4 T1/T2，`e4f80f7`/`4f5d547`；本轮核实状态）：v1 裁决 A+C——用户自担 shell 命令模板（`{{LIGHTAMER_MCP}}` 端点文件 + `{{PROMPT}}` 占位符）+ `/bin/zsh -c` 执行 + app 侧串行（至多 1 agent 进程）+ 终止只及自家（SIGTERM→5s→SIGKILL）+ 日志面板（环形缓冲 2000/跟随滚动/复制/写回计数诚实面）。
- **通知/长任务**：v1 同步 req/resp，MCP progress notification 不用（长渲染 = 超时错误）——Alcedo 的 `tasks.wait`/`watch` 语义我方 v1 刻意不做。
- **范围红线（by-design）**：无删除/移动/任意路径写/像素工具（MCP-08 封闭集证明）；无导入工具。

### 3.2 AI 五件套（Phase 07 + M2-10 + M4-3 交付，全在产）

| 能力 | 我方实现 | 对照 Alcedo |
| --- | --- | --- |
| 本地 CLIP 检索 | `LightamerCore/Sources/AI/SemanticEngine.swift`（Chinese-CLIP CoreML 224px 双塔 L2 归一化 in-graph + vDSP 全量扫）+ `SemanticStore` + GlobalSearchDialog CLIP 腿（M2-10-02） | 对齐（我方中文 CLIP 更强；Alcedo = MobileCLIP ONNX 512 维） |
| 自动打标 | `LabelEngine.swift`（余弦 top-8/margin≥0.05/confident + top_scores JSON——Alcedo SemanticImageLabel 语义）+ 导入管线（M2-10-03） | 对齐 |
| AI 描述 | `AIDescriptionService.swift`（caption/tags/scene/confidence + `ai_understanding`/`ai_understanding_fts` FTS5 读面 + rendition_kind edited/original） | 对齐（Alcedo = DuckDB BM25；我方 = SQLite FTS5） |
| AI 评分 | `AIRatingService.swift`（rubric→远程→verdict parse clamp/sentinel→`ai_rating` append→**confirm gate**→`images.rating`；prompt_profile_id FNV 守护） | **超集**（confirm gate 为我方独有；sentinel 形即 Alcedo ai_rating.cpp:11-19） |
| 推理进程隔离 | `App/Sources/Lightamer/AI/AIWorkerMain.swift`（独立 worker 进程三腿：mask/depth/enhance；`AIInferencing` 协议缝可换 InProcess/Worker conformer） | 对齐（Alcedo = gRPC sidecar 进程；形态不同目标同） |
| 远程 provider | `AIProviderClient.swift`（OpenAI-compatible + Anthropic Messages 手写 Codable 零 SDK）+ `AIEndpointPolicy.swift`（https-only + loopback 白名单双门）+ `AICredentialStore.swift`（Keychain kSecClassGenericPassword） | 对齐（Alcedo 5 provider 专项适配 vs 我方 2 协议通用——openrouter 走 openai-compatible 可覆盖；volcengine/codex-oauth 为缺口但低价值） |
| 模型资产 | `ModelAssetCatalog`/`ModelAssetStore`（bundled chinese-clip-vitb16-int8 + realesr-general-x4v3；release jina-clip-v2 + real-esrgan-x4plus + drunet-color + depth-anything-v2-small；SHA-256 digest 锁 + 三源下载 + 确定性 zip 构建脚本） | **超集**（LightCraft 纪律：digest/断点/合成自检；Alcedo 仅 hf-mirror + sidecar 内下载开关） |
| 内置分割/深度/增强蒙版 | `AIMaskService`（Vision 层 A/B subject lifting）+ `DepthMaskPipeline`（DA V2 Small×worker，M4-3）+ `EnhanceEngine`/`TileInference`（SR/降噪可编辑副本） | **超集**（Alcedo 图库 AI 无蒙版/深度/增强面） |
| 神经 demosaic | 无（CIRAW Neural Engine 路线，Conventions 钉死不追） | 缺（by-design） |

### 3.3 MCP 对照结论

Alcedo AU15（MCP server）**未实现**；我方 20 工具 + launcher 已在产。**编排面我方领先约一个 Phase**；「照抄」在本面的正确姿势不是抄实现，而是抄 Alcedo 已实现而 MCP 面缺的**命令语义**（§4 gap 标「缺」各行）。

---

## 4. Gap map——CLI/编排面（逐行）

> 状态词：**已有**（我方工具面直接覆盖）/ **等价**（形态不同语义同）/ **缺**（可抄）/ **缺(by-design)**（不抄，安全红线）/ **可选**（低价值裁量）。

| # | Alcedo 面 | 我方对应 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| 1 | 独立 CLI 二进制（call/batch/watch/schema/version） | 无独立 CLI；`--mcp-stdio/--mcp-http` + 20 工具 | **可选** | MCP 覆盖 agent 场景；one-shot shell 用例未被用户需求拉动；CI 测试驱动已有 test-direct.sh 直启，不需要 CLI 测试通道 |
| 2 | 会话发现文件（socket/pid/host_mode） | `mcp-endpoint.json`（port/token/pid/host/health） | **等价** | 发现协议语义同构 |
| 3 | `session start/stop/list/prune`（headless 宿主生命周期） | `--mcp-stdio`（agent 自管生命周期）+ launcher；无 list/prune | **缺** | 无头 daemon 的 list/prune 语义在 stdio 形态下意义弱化；HTTP daemon 形态若启用再补 |
| 4 | `project.create/open/save/close` 4 命令 | 无 MCP project 工具 | **缺** | 打开项目/建项目是 agent 全流程第一步；高价值 additive |
| 5 | `library.import` | 无（任意路径导入 = 安全红线） | **缺(by-design)** | 不抄 |
| 6 | `library.list`/`library.info` | `list_photos`（25 列投影 + 游标分页） | **已有** | 我方投影列更宽 |
| 7 | `library.thumbnail`/`library.thumbnails`（contact sheet） | `get_thumbnails`/`get_contact_sheet` | **已有** | Alcedo 的 contact-sheet 用例我方原生覆盖 |
| 8 | `library.folders` | 无（我方 Sessions/相册模型不同） | **可选** | 相册树工具待我方图库面定型后议 |
| 9 | `library.selection.get/set` | 无 | **可选** | GUI 选区联动，agent 场景价值低 |
| 10 | `library.rate`（0..5） | `set_rating`+`set_flag`+`set_color_label`+`append_note`+`set_keywords` | **已有** | 我方超集 |
| 11 | `library.delete` | 无（MCP-08 封闭集：无删除/移动） | **缺(by-design)** | 不抄 |
| 12 | `editor.open/close` | `load_image` | **已有** | |
| 13 | `editor.catalog`（参数目录 UI 单位） | `list_iops` + IopCatalog（18 iop 参数 schema + 版本键） | **已有** | 语义同构（机器可读参数自描述） |
| 14 | `editor.get/set/batch_set`（UI 单位读写 + note） | `apply_params`（单图写；无跨图批量、无 note/author） | **已有(单图)** + **缺(跨图批量/attribution)** | 跨图批量见 #16；attribution 见 #21 |
| 15 | `editor.undo/redo/history` | 无 history 工具 | **缺** | history 只读面（含 author/note）高价值——agent 自查编辑序列 |
| 16 | `adjustments.items/copy/paste`（跨图调色复制） | GUI Copy Adjustments 有（M2-8 transfer service）；MCP 无工具 | **缺** | agent 批量统一调色的核心动词；可复用 adjustment_transfer_service 做工具壳 |
| 17 | `versions.list/create/branch/checkout/rename/remove` 6 命令 | GUI 版本面有（M2-8）；MCP 无 | **缺** | 至少只读 `versions.list`；变更类命令与单写者纪律相容（经 actor 串行） |
| 18 | `render.preview`（`compare: root` 原图对比 + `region` + `file_stem`） | `render_preview`（分辨率/格式参数化；无 compare/region） | **已有(主腿)** + **缺(compare/region)** | before/after 对比图是 agent 自评调色效果的关键反馈回路；高价值 |
| 19 | `export.options`/`export.status` | `export_image` 同步单图；无 options 自描述/队列状态 | **已有(run)** + **缺(options/status)** | 小缺口 |
| 20 | `search.query`（EXIF/fuzzy，命中 AI FTS+标签+评分） | 无 MCP 搜索工具（GUI 三段搜索全真实） | **缺** | **最大单点缺口**——agent 无检索动词，只能 list_photos 逐页扫；语义/全文/EXIF 统一 search 工具 = 高价值 |
| 21 | commit attribution（`editor.set note` + history author=agent + 面板显示） | apply_params 无 note；history 无 author 概念 | **缺** | M2-8 版本/历史面板已有人读面；缺 agent 身份标注缝（写工具加 note + 编辑历史记 author） |
| 22 | `state.get`（统一状态快照） | 无统一 state 工具（分散在 list_photos/list_iops 等） | **缺** | 小 |
| 23 | `control.acquire/release/get`（GUI turn-taking） | 无（单写者锁纪律不同：server 单实例 + GUI-live typed error） | **缺** | 见 §5 Wave B——Alcedo AU14 的「人与 agent 共驾一 GUI 会话」体验我方完全没有 |
| 24 | `tasks.list/wait`（后台任务等待） | 无（v1 同步 req/resp；长任务超时） | **可选** | 若引入跨图批量任务（#16 paste 语义）则升级为必要 |
| 25 | `watch`（通知流）/ `history.changed`/`task.updated` 等 5 通知 | MCP notification v1 不用 | **可选** | launcher 日志面板部分替代（GUI 侧可见性） |
| 26 | `lut.list` | 无 MCP LUT 工具 | **缺** | 小；LUT 库面已有（M2-5），工具壳薄 |
| 27 | agent 操作 skill 文档仓（alcedo-skills：SKILL.md + CLI reference 自动生成） | 无 | **缺** | 低成本高价值；含会话启动/工具语义/错误码/预览工作流/UI 单位，不含 taste |

**计数**：27 行 = 已有/等价 12 + 缺(可抄) 9（#3,4,15,16,17,18,20,21,22,26,27 中按 #14/#18 拆分口径——核心缺口 9 个）+ 缺(by-design) 2 + 可选 4。

---

## 5. 「照抄」范围建议（charter 切分草案）

> AI 面（§3.2）已对齐/超集，**不设 AI 波次**；建议 charter 三块 + 波次如下（供 `$gsd-manager` 裁量，非 plan）。

### 块一：编排面 additive（MCP 工具补齐）——性价比最高，纯 additive

- **Wave O1「检索与状态读面」**：MCP `search_photos` 工具（EXIF/全文/CLIP 语义三路由对齐 GUI 三段搜索——复用 FilterSQL/SemanticEngine/LabelQueries 单源）+ `get_history`（编辑历史只读，含 note）+ `get_state`（状态快照）。工具面 additive，快照显式改（D-14-CONTEXT-3 机制内）。
- **Wave O2「反馈回路」**：`render_preview` 加 `compare:"root"` + `region` 参数（before/after + ROI——对齐 Alcedo render.preview 语义，agent 自评调色的反馈闭环）+ `list_luts`。
- **Wave O3「项目与版本」**：`project_open`/`project_create` + `list_versions`（只读优先；版本变更类工具视单写者余量二期）。
- **Wave O4「跨图批量」**：`copy_adjustments`/`paste_adjustments`（复用 M2-8 adjustment_transfer_service；若走后台任务则补 `list_tasks`/`wait_task`，Alcedo tasks.wait 语义此时一并引入）+ 写工具 `note` 字段（commit attribution 第一步）。

### 块二：GUI agent 控制权（turn-taking）——Alcedo AU14 语义移植，charter 级决策点

- 语义：agent 持锁时 GUI 禁编辑保留浏览（我方对应 = 编辑面板/命令面只读化）、agent 活动在 GUI 可见可停（我方落点 = Toast/任务面 + MCP server 面板扩展）、Stop 后同 agent 可恢复。
- 依赖：M2-9-A 单写者锁（LightCraft MCP 单写者 + `--connect` 转发已挂账）——**建议与 M2-9-A 合并立项**，不单飞。
- 我方裁量点：我方已有「GUI-live 图写 typed error」最简版；是否上全套 turn-taking（UI 禁编辑 + activity 卡）= charter 决策。

### 块三：CLI one-shot 动词（可选，低优先）

- 若做：`lightamer-cli` thin client = MCP HTTP 客户端 one-shot 包装（`call/batch/watch/schema/version/session` 子命令、5 档退出码、`--json`），复用 mcp-endpoint.json 发现。
- 若不做（v1 裁决 MCP-only 的自然延伸）：stdio MCP + launcher 已覆盖 agent 场景；shell 脚本用户可用 `curl`+endpoint 文件。**建议默认不做，挂账等真实需求**。

### 附带件（任何块顺手）

- **agent 操作 skill**（对齐 alcedo-skills）：仓内 `docs/` 或独立 `lightamer-skills` 仓——会话启动（stdio 配置模板）/20 工具语义边界/错误码表/render_preview 预览语义（编辑态无印框）/UI 单位说明；reference 可从 tools/list 快照机检生成（对齐 generate_cli_reference.py 思路）。**不含 taste 规则**（Alcedo 同款排除，taste 留给用户自配 prompt 模板——launcher `{{PROMPT}}` 已是载体）。
- **写工具 note/author 缝**：apply_params/paste 类工具加 `note` 参数 + 编辑历史记 agent 身份（块一 O4 或独立小 plan）。

---

## 6. 许可边界（GPL 零复制声明）

- Alcedo Studio = GPL-3.0-only（`LICENSE`；源文件头 `SPDX-License-Identifier: GPL-3.0-only` + GPLv3 §7 additional permission）。**只读参考功能行为/命令语义/交互设计；代码零复制入库**（本项目 MIT）——与 darktable/AlcedoStudio 参考先例同纪律（CONVENTIONS.md 参考项目节）。
- **功能行为克隆合法**：命令名/参数名/JSON-RPC 方法名/工具名/退出码档位属功能面不受版权保护；且我方主 surface = MCP 工具（snake_case 命名空间）与 Alcedo CLI（点分 JSON-RPC）天然异构，无逐字 copying 面。
- 需要注意的两点：①若未来引入 Alcedo 的文档文案（skill 正文/描述文本）——**禁止翻译或改写其 GPL 文档**，全部自写；②`alcedo-skills` 外部仓内容同 GPL，同规。
- 我方对照实现全部走既有自有基建（FilterSQL/SemanticEngine/adjustment_transfer_service/ExportRenderer 单源），无 Alcedo 代码路径依赖。

---

## 7. 证据索引（file:line 快查）

**Alcedo CLI**：`alcedo_studio/src/ui/alcedo_cli/cli_commands.cpp`（usage :61-89；选项解析 :128-175；会话选择 :214-264；start :550-669；stop :671-718；list :730-769；prune :771-803；watch :805-835；batch :837-919；分派 :923-972）；`cli_commands.hpp:11-17`（退出码）；`main.cpp:11-20`；`CMakeLists.txt:1-15`（thin client 定义）；`include/automation/automation_protocol.hpp:18-37`（版本/行帽/错误码）；`include/automation/automation_client.hpp:20-40`；`include/automation/automation_session_file.hpp:15-60`；`include/ui/alcedo_main/automation/automation_server.hpp:20-30`（多连接/GUI 线程）；`include/ui/alcedo_main/automation/automation_control_commands.hpp:15-27`（control 语义）；`headless_host.hpp:18-57`（headless 选项/退出码）；命令注册 48 处 `ui/alcedo_main/automation/commands/*.cpp`（grep `method = QStringLiteral`）。
**Alcedo AI**：`rust/puerh_mind/proto/{common,ai_runtime,image_analysis,semantic}.proto`（26 RPC）；`rust/puerh_mind/Cargo.toml`（ort coreml/directml、rustls HTTPS-only）；`src/service/providers/`（5 适配器）；`include/app/ai_sidecar_runtime_service.hpp`（sidecar 编排）；`include/ai/{ai_description,ai_rating}.hpp`；`include/storage/store/ai/ai_store.hpp`（DuckDB+FTS）；`include/app/search_query_classifier.hpp:14-44`；`include/app/{ai_provider_profile,ai_credential_store}.hpp`；`app/semantic_generation_service.hpp`（打标管线）；`decoders/processor/nn/`（DemosaicNet）；`src/nn/safetensors.cpp`。
**Alcedo 计划**：`docs/roadmap/alcedo_studio/automation/cli_mcp_automation_plan.md`（§1.2 决策表/§1.3 排除/§2.5 通知/§2.6 命令目录/§2.7 CLI 行为/§2.8 agent control/§7 AU 阶段表/AU15 MCP 节）；AI 计划 = `docs/roadmap/alcedo_studio/ai/{semantic_generation_search_plan,ai_sidecar_backend_plan,ai_sidecar_phase0_requirements}.md`。
**关键 commits**：`7348201`(AU1 协议) `bad3b20`(AU2 CLI) `63876d9`(AU3 headless) `a6c8848`(AU14 agent control) `7e0c9cb`(agent 会话钉住+Stop) `c7ba784`(scopes 保活) `6a0fe59`(批量缩略/photo info/batch) `e75cf2a`(adjustments copy/paste) `d87e4b3`(lut.list) `1f12551`(输出防覆盖) `6203791`(FAIL 不覆盖) `c1a66b4`(prune 只删自己) `ace755e`(--version)。
**我方**：`App/Sources/Lightamer/MCP/`（20 工具 + launcher + 双宿主）；`LightamerCore/Sources/AI/`（AI 五件套 28 文件）；`App/Sources/Lightamer/AI/`（worker 面 10 文件）；Phase 14 正本 `.work/gsd/phases/14-mcp-server/`（14-CONTEXT D-14-CONTEXT-2/3/10）；M2-10 正本 `.work/gsd/phases/m2-10-ai-library/`；产品面正本 `.work/gsd/research/ALCEDO-FEATURE-MAP.md`。
