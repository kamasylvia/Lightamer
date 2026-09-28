# Plan 14-4 — 执行期决策（DECISIONS）

> 纪律条款：RESEARCH/CONTEXT 未覆盖的细节登记于此，不臆造。

## D-14-4-T1-1 union 宿主装配随 T1 探针退役同批落位

Plan 把「分域快照与终快照一致」记在 T3，但探针退役使 `makeRegistry` 的装配语义必须当
场重定（裸核 = 空），culling 14 工具接宿主装配（14-3 遗留「14-4 union assembly」）
与退役是同一装配缝的一次改动——拆两次提交只会制造一个中间态：宿主 7 工具的假面。故
T1 一次落位：`makeRegistry(editing:culling:)`、`runHeadless`/`startHTTPHost` 全部走
19 工具封闭面，stdio 三形态 hello 的 canonical call 即换 `list_iops` 并保持到终态，
避免 T3 二次改写测试。**影响：T1 提交含 culling 宿主装配 + GUI 生产 culling context。**

## D-14-4-T1-2 GUI 生产 culling context = McpWriteFaceBox 间接盒

culling 写面（metadata/sidecarWriter）必须是 GUI 的**共享** segment-3 writer 实例
（D-14-CONTEXT-5① 单源；每调用新建 BatchSidecarWriter = 私有序列化队列 = 违约）。因
writer/provider 每会话重建（sessionIndexHandler 内），用锁保护间接盒
`McpWriteFaceBox` 在重建点发布、teardown 点清空——MCP 闭包恒读当前对，宿主缝免逐会话
重接线。metadata 每次 Service 构造按 (root, store, box.writer, seed)（与
MetadataController.write 同形），seed = 启动时一次性 `seedInstances()`（默认链静态）。

## D-14-4-T1-3 headless 宿主 culling context = 诚实 no-session 形态

已交付 headless 宿主的 session provider 恒 `{ nil }`（无会话打开能力），故 culling
全部工具答 typed `notSessionMember`；`makeCullingContext` 的 metadata/writer 每调用按
session pair 构造的腿在该形态下永不触发（dormant）。写能力 v1 集中在 GUI 内嵌宿主
（launcher 路由即此）。无头会话打开 = v2 面（届时 writer-per-call 语义需重裁）。

## D-14-4-T1-4 Settings 存储键名（@AppStorage）

`mcp_server_enabled`（14-1 已落，T1 接控件）；新增 `mcp_lan_exposure_enabled`（0.0.0.0
gate）/ `mcp_agent_command_template` / `mcp_agent_prompt_template`。键名即常量源
（`McpServerController.lanExposureEnabledKey` / `McpLauncherTemplateKeys`）——设置 UI
与宿主/面板读同一拼写，无双源。LAN toggle 在宿主运行中切换 = stop+start 重启宿主（绑定
真实生效，不留半态）。

## D-14-4-T1-5 预置模板 = 设置占位文本（非落盘默认值）

omp/pi 两例（research §RQ-14-12 原文）放 TextEditor 空态 overlay（zh/en 键）；不预填
偏好值——用户的模板是「用户自己的命令」，app 不代写默认命令（零 AI 代码条款的精神边界）。

## D-14-4-T2-1 launcher 核 = 非 actor 的 NSLock 类 + 进程级 shared 单例

面板是独立 Window scene（与 preset-manager 同款独立窗口挂点 + Edit 菜单项
`menu_mcp_launcher`），核生命周期须跨越面板开关——`McpLauncher.shared` 进程级单例 +
`McpLauncherLogBuffer` 持续积累（面板重开 `syncFromCore` 追平）。锁而非 actor：测试与
管道读线程免 MainActor/actor hop（`@unchecked Sendable` + NSLock，与 14-1
EmbeddedState 同款姿势）。onLogLine/onExit 为单 slot tap（单面板窗口假设，v1 成立）。

## D-14-4-T2-2 面板 pre-flight 拒绝面（server 未启动 / 模板未配置）

server 未运行（发现态非 `.alive`）→ 提示「请先在设置中启用」+ 日志行，**不自动代启**——
一键语义是「拉起 agent」，不是「改用户的服务器配置」；模板为空同理提示不代填。两处均为
诚实提示（zh/en 键），非静默 no-op。

## D-14-4-T2-3 「本次会话无写回」的计数正本 = registry requiresWriter 调用计数

agent 是否听话不作断言（plan 诚实条款）——app 侧可观测的正本只有 server 自己：actor 级
`writeCallCount`，**requiresWriter 完成调用**才 +1（只读降级 gated-out 不算写回）。面板
取会话起止 delta。五个写工具 + apply_params/apply_preset/export_image 全部
`requiresWriter: true`，计数无需逐工具胶水。server 重启导致起点缺失时按诚实零报告。

## D-14-4-T2-4 日志面板 = ScrollView + Text（非 TextEditor）

要求面是「显示 + 暂停滚动 + 复制全文」：ScrollViewReader + 跟随开关驱动 scrollTo（OFF =
视口冻结），文本 `.textSelection` 可选不依赖 TextEditor 编辑语义；复制走 NSPasteboard
全环导出（v1 无文件导出，research 同款）。环形裁剪镜像核侧 2000 行帽。

## D-14-4-T2-5 L010 走查记录

面板/设置新控件全部可见文字标签 + `accessibilityIdentifier`（`settings.mcp.*` /
`mcp.launcher.*`），无容器级 accessibilityLabel 吞子元素 AX；日志 ScrollView 无 AX 标签
（内容 Text 裸露可读）。哨兵测试不重复 AX 断言（控件无 label 遮蔽即无吞面）。

## D-14-4-T3-1 工具描述 zh 化 = defaultValue 包裹法（en 零漂移）

D-14-CONTEXT-3②「zh/en 双语描述进 String Catalog」在 14-2/14-3 未落地（描述为内联英
文），14-4 收口兑现：15 键（write-five 共享 frame 一键，`mcp_tool_desc_write_metadata`）
——`String(localized: "mcp_tool_desc_<name>", defaultValue: String.LocalizationValue(<原
表达式>))`：en = 原审定文本**逐字节**（编译期常量串直接作 defaultValue，目录不放 en 副本
= 零漂移零双源），zh = 简明忠实译文入 catalog。快照/InMemory echo 测试不改（描述不 pin
字节，只 pin 非空）。运行时按 app 语言出描述（agent 面默认 en 不变）。

## D-14-4-T3-2 终快照正本与 destructive 计数

终表正本 = research §A（19 行）；annotations 列在终测落为集合断言：**8 destructive**
（apply_params/export_image + 写五 + apply_preset）/ 11 read——§A 表逐行核对。

## D-14-4-T3-3 SC#7 链测试的 agent 形态 = curl 哨兵（真实 client 形态）

「launcher 拉起 agent」的自动化腿用 `/bin/zsh -c` + curl 子进程：与真实外部 agent 同走
Streamable HTTP + JSON-RPC + `mcp-session-id`（非进程内捷径），launcher 核真实 spawn。
发现文件 → port 的提取用 tr/grep（POSIX 工具链，无 python 依赖）；每 curl `--max-time 20`
+ `set -e`（任一腿失败 = 非零退出红面）。SSE `data:` 解析宽容化（空载荷行跳过 + 解析失败
回退原文）——执行期踩坑：空 `data:` 行曾致 JSON 抛错且被任务取消语义掩盖（LESSONS L032）。

## D-14-4-T3-4 get_face_regions 超时档 → thumbnailsAndContact（20s）

14-3 验收注记兑现：RAW 解码腿 10s list 档偏紧；挪 20s 图像档（快照不 pin 超时，行为测试
无感）。burst 2.0s 含边界补钉 = `testBurstGapExactlyAtThresholdStays`（同验收注记）。

## D-14-4-T3-5 15 键而非 19 键的偏差留痕

AC 字面「每工具 zh/en 描述键存在」——源码现实是 write-five 共享一个 frame 描述（一次
registerOne），19 工具对应 **15 个去重描述键**；测试键映射表
（`McpFinalSnapshotTests.descriptionKeys`）19→15 全覆盖断言。若 v2 给写五件分工具化描
述，加键即可（additive）。

## D-14-4-T4-1 探针退役的 StoreProvider 缝一并删除

`count_images` 是 `StoreProvider` 的唯一消费方——退役即删（`startHTTPHost` 签名收紧），
不留死参数。14-1/14-2/14-3 测试调用点同批适配（McpHostTests ×8 / ParityTests ×1）。
