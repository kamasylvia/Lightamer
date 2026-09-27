# 13-2 SUMMARY — 色彩完备（COLOR-02/03，D-COL3 预留位兑现）

> 执行：2026-09-27，executor subagent worker（T1-T6）+ 续班 executor（T6 后 forensics 修复批 + T7 收尾；前任 worker 因系统 swap thrashing 崩机中断，WIP 经审查完整接用）。
> 分工：执行 = worker（AGENTS.md Phase 执行模型）；软打样零回归硬闸 + BPC 探针硬序全程遵守。

## 任务表

| 任务 | 内容 | commit | 验证 |
|---|---|---|---|
| T1 | BPC 可达性探针（头项硬闸）：ObjC CLI v1-v8 迭代，CGColorConversionInfo API 面全核查 | `3d52fa4` | `13-2-probes.md` 落盘（先于 T2，硬序遵守）：BPC 公开开关存在且被消费（分化锚）+ intent 行为锚 + CMYK 四通道全不可达 → 管线形状 = 公开开关直用 + CMYK 降级（D-13-2-1/2） |
| T2 | 软打样 proof 段：`SoftProofProfile`（值类型 + per-run override 语义 doc 锁死）+ `SoftProofStage`（iopOrder 69.5 非 registry 模块，Rec2020→printer ICC→Rec2020 ColorSync 往返）+ PipeCoordinator `setSoftProof` 注入面 | `7096375` | `SoftProofStageTests` 10/10：OFF 逐字节直通（box absent 非 disabled）/ 域内往返精确 / OOG clip / BPC 锚 / CMYK+非 relative typed 拒绝 / stableID 纪律 / registry 缺席（结构性 never-Params/history/sidecar/export 证明）/ hash 折叠 / catalog |
| T3 | OOG gamut check：往返 delta 阈值 1e-3 判定 + 黑裁剪 + 关闭直通对照 | `7fd4442` | +2 golden（`testGamutCheckBlackClipsOutOfGamut` / `testGamutCheckOffPassesProofValues`）；样本构成 = T1 探针锚集（D-13-2-OOG） |
| T4 | proof UI 面：视口 top-trailing 悬浮胶囊（塌缩显示 printer+OOG 警示）+ View 菜单 ⌥⌘P + recency 5 条 + typed 拒绝 toast + 文案显示语义纪律 | `0860c88` | `SoftProofUIWiringTests` 7/7（toggle 无选择拒绝/激活+recency/CMYK 拒绝不扰 armed proof/关闭清 coordinator/gamut re-commit identity/recency 去重上限/L025 smoke）；zh 8 键同批 |
| T5 | 多显示器 ICC golden：事件面复核 = 02-04 底座已落，增量 = golden 钉死全行为（零新代码） | `ebeb007` | `MultiDisplayProfileTests` 4 golden：切换仅重渲 colorout+gamma 两平面且上游平面存活（SC#2 terminal variant 端到端）/ 双窗双屏独立 / proof override 同纪律 / 双屏信号 + 窗口所在屏优先源级锚 |
| T6 | 手动 per-display 覆盖：`ManualDisplayOverrideStore`（displayID→ICC path，precedence > 自动解析，stale 优雅降级）+ SettingsView Displays 段 + exact-TRC parser（matrix-shaper XYZType 含 4 字节签名+4 保留字节） | `abe47bc` | +5 测试：override 字节 identity / fallback 腿 / precedence+clear / 缺文件降级 / linear variant 解析 identity（AdobeRGB primaries 非 sRGB）；zh 6 键同批 |
| 修复批 | **exact-TRC render leg 回退 deferred**（forensics：per-render CGColorSpace 实例 churn → CI 腿 order-sensitive → 字节精确套件间歇全黑平面 flake + CullingPipeline collapse；归因与三件处置 = D-13-2-7） | 本批（续班 executor） | `LinearVariantCache`（per-ICC-byte-hash 含 nil verdict 缓存）+ render leg 回 singleton workalike + parser capability 保留；`MultiDisplayProfileTests` 9/9 绿（断言同步改钉 workalike 基线） |
| T7 | F-12-5-2 材料包 + 全套终轮 + SUMMARY/DECISIONS + TODO/PROGRESS | 本提交 | 材料包 `.work/gui-acceptance/13-2-f12-5-2/`（判定归 13-4，D-13-2-8）；终轮见下 |

## 回归计数（T7 终轮）

- 基线 **1574/10skip/0fail**（13-1 验收终值）
- 本 plan 新增测试：**28**（SoftProofStageTests 12 = T2 10 + T3 2；SoftProofUIWiringTests 7 = T4；MultiDisplayProfileTests 9 = T5 4 + T6 5；零 skip——13-2 测试全门控自由）
- 目标类单跑（修复批后复验）：MultiDisplayProfileTests 9/0 fail（0.86s）+ SoftProofStageTests 12/0（0.04s）+ SoftProofUIWiringTests 7/0（0.08s）
- **终轮：1602 / 10skip / 0fail（656.1s）EXIT=0**（caffeinate -dis Scripts/test-direct.sh 直启；1574 + 28 = 1602 精确吻合）
- 在案负载型 flake（LayerE2ERoundTripTests / ToneEqualPerf）：本轮 4 条全 passed，未现身
- **内存观察**（承接 PROGRESS 16-2 内存事件备忘策略）：全套前确认无 GUI app 残留实例；跑测期间 swap 监控峰值 **5.9GB**（判据 8GB 未触；host RSS 峰值 <0.5GB，上次崩机场景的 10.4GB 未复现）；收尾后 pgrep 校验宿主零残留，swap 回落 1.9GB
- 观察注记：本轮全套时长 656s（13-1 为 511s）——软打样 ColorSync 转换 + 负载段波动，属正常带宽外延，无 fail 无超时

## 证据指针

- BPC 可达性矩阵 + 行为锚 + 管线形状判定：`13-2-probes.md`（T1 正本；探针源 `/tmp/la-bpc-probe*.m` 不入 repo）
- 执行期决策 10 条 + grep 教训候选：`13-2-DECISIONS.md`（D-13-2-7 forensics / D-13-2-OOG 样本构成为源码引用锚）
- never-Params/history/sidecar/export 四断言：`testStageIsNotARegistryModule`（结构性缺席）+ `SoftProofProfile` doc comment 契约 + `ExportChainBuilder` 从 records 装配（stage 永不入 records）
- F-12-5-2 对照规程与材料：`.work/gui-acceptance/13-2-f12-5-2/README.md`

## GUI / Manual-Only 域（13-4 走查批承接）

- **F-12-5-2**：dt-GUI 人工交叉对照（材料包已备齐，规程 5 步，人眼判定归 13-4——D-13-2-8）
- **真双屏切换实测**：多显示器通知 + window↔screen 追踪的 live 走查（自动化腿已源级锚钉，观感项候补 Manual-Only）
- proof 胶囊/Settings Displays 段真机观感（wiring 已单测钉死；候补 Manual-Only）

## 人工阻塞项提醒（义务履行，D-13-2-10）

Developer ID 证书与私钥 / App Store Connect API key / GitHub 公开仓时机——13-4 排期前必须由用户供件（GOAL-STATE 阻塞节由 orchestrator 汇总时同步）。
