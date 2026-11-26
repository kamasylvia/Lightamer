# FRAMEWORK — 学 LightCraft、兼容 darktable 的框架结论

> 日期 2026-11-26。LC 树 HEAD `0da998f2`（= LIGHTCRAFT-NOTES §七锚，本地 10-16 后无更新）。
> 行数由 `wc -l` / `grep -c` 当日重跑。长表见 `FRAMEWORK-TABLES.md`（T-F*）。
> 结论先行、证据随后；无证据判断标「推断」。

## §0 One page（新布局 / 取舍计数 / 阶段 A 新表 / 三大调和难点）

```text
L0 dt-geom dt-raster dt-color-math dt-iop-traits dt-sysmem
L1 dt-iop-raw/geom/color/display  dt-meta dt-color dt-blend dt-decode dt-scenes
L2 dt-registry → dt-history → dt-pipeline        （同层链，严格向下）
L3 dt-catalog dt-preview dt-apple(仅macOS)  [dt-gpu dt-merge dt-lightamer 占位]
L4 dt-engine（含export/memory/import/作业）     L5 dt-gpui [dt-mcp 占位]
Exempt apps/dt-cli xtask ｜ Testkit dt-testkit ｜ 退役 dt-api dt-app dt-export（fold 进 engine）
```

取舍：**照搬 8**（分层检查、never-crash lint、testkit、sysmem、LRU tick、process 规则、
activity 语义、owned-merge 纪律）、**改造 11**（命令注册表、execute+undo、规格单表、
JobPool、Preview/DiskCache、WorkGate、export 进度、库锁、GPU 回退、等价门、parity 门）、
**不学 9**（自研解码、egui、跨平台底座、op-log、函数式管线形态、crs 映射内容、
LR/Luminar 导入、人脸等外围、字体分发）。

阶段 A 新表（10 波 20 lane 51.5h）：A1(1) A2(2) A3(3) **A3R(2，新：重排+分层检查)**
A4a(1) A4b(3) A5(2) A6(1) **A7a(3，重做：命令分发口)** A7b(2)。
B 76→80 lane（B13+1 B15+2 B16+1）。合计 93→100 lane，251.5h→271.5h。

三大调和难点：① 设置模型：LC 强类型 serde 对 dt 整块 POD blob——以 blob 为真相、
描述加访问器桥接（C1）。② 管线形态：LC 固定五段函数管线对 dt 57 回调+ROI+tiling——
不管线照搬，只取缓存键/窗口渲染/参考在先的纪律（C2）。③ 真相与版本：LC 单真相+process
版本对 dt 双存+modversion 迁移——SQLite 真相 + dt 键字节保留 + 自有 process 版本（C3/C5）。

---

## §1 Layering（F1 分层）

LC 分层由 `LC/xtask/src/layers.rs`（316 行）强制，入口 `xtask/src/main.rs:201 cmd_layers`，
编入 `ci :364`。规则：TABLE 登记（`:35-71`，见 T-F1）、严格向下（同层默认也违规，
除 `INTRA_LAYER_ORDER :76-85` 链）、UI 名单（`UI_CRATES :97`，`UI_MIN_LAYER=5 :100`）、
testkit 只许 dev 依赖。五类违规见 T-F1。不查：传递依赖（`--no-deps` 只有直接边）、
外部版本/feature、Exempt crate 的边、悬空 TABLE 条目（`export` 已无 crate 但条目仍在，
LC 导出实现在 `engine/src/export.rs` 3472 行——「export 曾为 crate 后被 fold 进 engine」为推断）。
`Standalone` 类 TABLE 中零使用。与 `docs/architecture.md`（10-10 快照）的不一致：
`heif` 文档 L1、代码 L0；文档漏 `lensdb/inpaint/geocode/slideshow`。
结论：机制照搬（T-F10#1），TABLE 换 T-F9 新布局；dt 侧无对应物，零冲突。

## §2 Engine and commands（F2 引擎与命令）

命令声明 `CommandSpec{id,label,menu,shortcut,params,enabled,run,journal,explicit_targets}`
（`engine/src/cmd/mod.rs:53-69`），`Run/Enabled` 为函数指针（`:50-51`），宏 `cmd! :129-134`，
聚合 `command_specs :139`，查找 `find_command :184`。参数全是 `serde_json::Value`，
`params` 字段只是 `&'static str` 文档——**机器可读 schema 查不到**（`mcp.md` 明说 registry
只有 prose docs；`tools.rs:check_args` 只对 helper 判未知键）。分发口唯一：
`Session::execute`（`engine/src/lib.rs:512-513`，注释 `THE entry point for every frontend`），
UI 总口 `LightcraftApp::run`（`ui-egui/src/lib.rs:595`）先查 UI 表（`menus.rs:411`）再进 engine。
六前端（任务书说五个，实测六个：UI/控制通道/CLI/MCP/headless/Web）共用经过 T-F2 表；
UI-only 命令另表 `menus.rs:61 UI_COMMANDS`。历史：命令内 `commit(Op) :587` 即记一步
（上限 1000），`edit.undo/redo` 只是调 `undo_step/redo_step`（`:724/:749`）；后台写入走
`apply_system` 不记撤销；持久库每命令后 fsync（control-protocol.md 原文）。
作业无中央队列：Activity 注册表（`activity.rs` 438 行）+ 各自 worker（渲染 dispatch、
导出 `run_batch(progress->bool)`、预览 task_for），取消一律 `AtomicBool` 下张/下帧前检查。
MCP：`Backend` trait（`mcp/src/backend.rs:14`），headless 直调、connect 经控制通道薄转发，
**已发出后断线不重发**（`:140`，防 undo 执行两次）。单写者锁 `catalog.lock` + owner 文件
（`catalog/src/lock.rs` 162 行，`try_lock`），加锁点 `library.rs:410`。
下层不知 UI：engine 依赖无 UI crate + 源码零 egui 引用（3 处注释除外）+ layers 检查
（含单测 `:295-299` 断言 engine 引 UI 即错）。结论：骨架改造取用（T-F10#10/#11），
命令集按 dt 重写；params 无 schema 是 LC 缺口，我们不继承——面板描述（A3 Control 数组）
即是我们的 schema。

## §3 Editing model（F3 编辑模型）

`DevelopSettings` 是全 `#[serde(default)]` 纯数据（`develop/src/settings.rs` 1193 行，
头注释「unknown fields are ignored, missing fields take defaults」）。控制规格单表
`CONTROLS`（`controls.rs:144`，122 行已数得）+ `INDEXED` 10 模板（`pointColor.<i>.*` 寻址），
表头自述三消费方（UI 建面板 / MCP schema / get-set 按 id），已逐一核实调用点（T-F3）。
process 版本：`ProcessVersion(pub u32)`，规则正本 `docs/process-versions.md`——
「改观感即开新号，V1 冻结」；缺/坏字段读 V1；V1 序列化省略（保老预览 key 不变）；
copy/paste/preset 不携带（`process` 不在任何 `SettingsGroup`）；`Update to Current Process`
显式升级；未知大号保留并按本 build 最新渲染。`hash64`（FNV over settings JSON）是全部
缓存键的核。管线按 `s.process.process()` 分支（`finish.rs:282`），缓存 key 含 process
（`BaseKey`）。结论：规则照搬落 dt-history（类型）+ dt-catalog（列）+ dt-engine（命令），
见 C3/C5 调和。

## §4 Pipeline（F4 管线）

LC **无 stage trait**：`pipeline/src/lib.rs`（740 行）是五段自由函数管线
（geometry → scene-linear → tone map → colour → display，`:1-30`），CPU 整帧无分块，
`StageCache`（容量 2）缓存 `{geo,sampled,lin,planes}`，三级 key（geo/pre_nr/lin_key），
拖 tone 只重跑 per-pixel。Zoom 用 `RenderRequest.window` + 工作窗扩大。GPU 是同构 WGSL
（`gpu/src/render.rs:580`，MODULES 注册 `ctx.rs:1-123`），行带 dispatch
（`BAND_PIXELS=4M`），短提交（`FLUSH_INVOCATIONS=16M`），缓冲池复用（默认 256MB，
`ctx.rs:208`——旧笔记写 ≤2GB 已对不上），alpha-255 完整性检查（`:747-753`；"canary"
一词全仓 0 命中），全黑复算 CPU，两级回退（Limit/OOM/Blank 本张 CPU；Fatal 整进程 CPU），
`gpu-init.marker` 崩溃哨兵。内存：`sysmem`（80 行）只做 `release_free_memory` 不管配额；
配额在 `engine/src/memory.rs`（318 行）：预算 RAM/4（钳 256MB–1.5GB），引擎缓存 1/2、
`work_gate` 1/4、GPU 池 1/8、导出 gate 2×budget；`WorkGate{acquire/acquire_urgent}+Permit`
（`:99-160`），后台解码等房间、前台不定。取消：渲染作业无中途取消（推断，查过 pool 全文），
靠 per-slot 去重 + latest-wins 跑完即弃（`pool.rs` 359 行 + `render.rs` request/collect）。
结论：管线形态不学（C2）；JobPool、LRU、WorkGate、回退阶梯结构取用（T-F10#3–#8）。

## §5 Library and batch（F5 图库与批量）

存储 = `catalog.snap`（temp+fsync+rename）+ `catalog.log`（JSON lines `{seq,crc,op}`，
CRC-32，append 后 fsync 才返回）+ 后台 compaction + `SnapshotPolicy{2000 条, 16MB}`
（`catalog/src/journal.rs` 709 行，`VERSION=9`）。崩溃四规则已核实（T-F5）。
提交链：`commit` 内存 apply → `pending_log` → 每顶层命令后 `persist()` 一次 append。
预览三级（Thumb ≤512 / Preview ≤2560 / Full 最新）+ 128 位 key + 嵌入 JPEG 占位
（`QuickJob`）+ 邻居预取 + 磁盘 `.lcthumb`（QUALITY=90，7 天 STALE，超预算剪 80%）。
**三个性能数查不到**：347ms / 0.72s / 0.5s 在 docs + crates 全文 grep 无命中
（命令见 §13）；机制可定性：批量粘贴 = 单 `Op::Batch` 一次提交、缩略图按需延迟重渲
（`develop.rs:782-875` + key miss 才渲染）；热切换/缩略图 = 磁盘缓存 + 占位 + 预取 + 去重。
A-10 的门照用（用户已裁），B15/B16/B20 实测填数。结论：持久化不学（SQLite 代差已定），
预览缓存全套改造取用（B15 +2 lane）。

## §6 Metadata and XMP（F6 元数据与 XMP）

`lc:`（`http://ns.lightcraft.app/lc/1.0/`）只写 `settings/flag/location`
（`sidecar.rs:331-369`）。owned 17 项 + 条件 4 项（`:375/:398`），`merge_xmp`
（`meta/src/xmp_merge.rs:205`，442 行）一次扫描定位字节区间：owned 全删重写、
外来（`crs:/xmpMM:/lr:hierarchicalSubject`/注释/padding）逐字节拷，新属性进独立
Description；不可读先备份 `.bak` 再替换。`crs:` 只读近似映射（`crs.rs:191 to_partial`，
约 74 + 32 + 7 + WB 组；表正本 `docs/xmp-interop.md`），从不写回，
`AlreadyApplied=True` 跳过，`crs:ProcessVersion` 忽略。结论：owned-merge 纪律照搬
（即 PLAN §2.4 末段已定语义的实现参考，待 A4a 选库后决定 port 面，T-F10#13）；
`crs:` 映射内容不学（我们读 dt 精确格式，无需近似）。

## §7 Engineering discipline（F7 工程纪律）

`testkit`（190 行单文件）：`skip!(Need,reason)` + JSONL 记录 + `ci` 汇总
（`ci_report.rs:24`，`main.rs:283-287`）。等价性门 `equivalence.rs`：
`MEAN_LSB=0.5 / MAX_LSB=3`（`:16-17`），只比 RGB 8-bit sRGB（`:58 diff`）；
`cases()` 31 组（旧笔记写 26，已对不上）；文档实测 M4 Pro 全 max 1、mean ≤0.0003。
never-crash 三层：AGENTS.md 规范 + crate 根 `#![deny(...)]`（31 文件命中）+
`clippy.toml` 测试放行 + `ci` clippy `-D warnings`；观察：`engine`/`meta` 根缺 inline deny
（workspace.lints 也不含六件套），`meta/src/xmp.rs:256,291-294` 生产 `.expect` 能编译——
LC 自有缺口，我们落地时补齐（全员 deny）。归属门 `assets.rs`（136 行）：40 种后缀必须被
ATTRIBUTION 覆盖 + 8 种 Adobe 格式永不入库 + 文件名禁词。parity 门 `parity.rs`（520 行）：
checklist 的 `cmd:/ctl:` 引用存在性 + 路径行号 + 加权统计 + gaps 重号检查。
结论：testkit 照搬；三门改造（T-F10#1/#14/#15）；lint 全员补齐。

## §8 Verdicts（F8 取舍清单）

全表 T-F8（照搬 8 / 改造 11 / 不学 9）。判定锚：A-9 三条不学（自研解码、egui、
跨平台底座）+ 模块自动发现不退（A3 照跑）+ SQLite 真相（HISTORY-COMPAT §9 D2 已裁）
+ CPU 先行（PLAN §1.2#2）+ Apple 独占模块（A6）。与旧笔记的差别：op-log 由「不需借鉴」
升为明确不学（SQLite 已定）；CPU oracle 由「架构性不可行」修正为「形态不学、纪律照搬」
（B1 就是我们的 oracle，只是 dt 形状）；`crs:` 映射由候选降为不学（精确读 dt，
无近似需求）；export 由独立 crate 改为 fold 进 engine（LC 实证）。

## §9 Mapping and layout（F9 映射表与新布局）

四方映射与新布局见 T-F9。关键决断：① dt-core 更名 dt-pipeline、dt-library 更名
dt-catalog（空壳改名，A3R 做）；② dt-api/dt-app/dt-export 退役，fold 进 dt-engine
（LC 实证：export 在 engine 内，命令/查询/事件即 registry + execute + Activity；
PresentSink 句柄思想保留为 engine 内的能力对象）；③ 新增 dt-sysmem/dt-preview/
dt-testkit/dt-meta/dt-scenes，dt-gpu/dt-merge/dt-mcp/dt-lightamer 占位空壳；
④ 同层链只一条 `[dt-registry, dt-history, dt-pipeline]`；⑤ A3 产物原位不动，
只改层号归属（traits L0、四域 L1、registry L2）。

## §10 Reusable code（F10 可取用代码）

17 项见 T-F10（11–15 含 NOTICE 模板 N1）。署名：LC 为 MIT OR Apache-2.0（任选其一），
与我方 GPL-3.0-or-later 兼容；LC 文件无独立许可头，逐文件加
`// Derived from lightcraft <path>` + NOTICE 登记（文件、提交 `0da998f2`、原样/改造说明）。
反向约束：LC 禁读 GPL，我们不受限；但它的相机矩阵/色彩拟合是估计值（ΔE 2.9–10），
永不作为我方色彩真相。C 期再取：`backend.rs` connect 转发（随 MCP）。

## §11 Plan impact（F11 对计划的影响）

阶段 A 新表与阶段 B 每卡见 T-F11。A：A1/A3/A4a/A4b/A5/A6/A7b 不变（A2/A4b/A5/A6 只改
crate 指向）；新增 A3R（重排 + 分层检查 + testkit，2 lane）；A7a 重做为命令分发口
（registry + execute + undo + activity + memory + headless + CLI run，3 lane）。
B：B1/B2（接线 work_gate 与 release hook，不加 lane）/B3–B12/B14/B17–B20 内容不变；
B13 +1（process 版本 + owned-merge 写回），B15 +2（预览缓存三件套 + 占位 + 预取），
B16 +1（activity 进度/取消 + 导出 gate）。桌面控制通道延期到 C 随 MCP（B 只留 CLI run 路）。
估时：+7 lane（A+3，B+4），93→100 lane，251.5h→271.5h（含自审 ≈326h ≈ 41 日）；减项无。

## §12 Conflicts（F12 拉不到一起的地方）

- **C1 设置模型 vs dt 整块参数**：LC 强类型 serde 字段 + 控制表直接读写；dt blob 不透明，
  字段语义只在 C 结构体。调和：blob 仍是真相与持久化格式；A3 Control 描述加
  `offset/size/解码` 访问器，engine get/set 经访问器读写 blob（面板/命令/MCP 同源）。
  代价：每模块约 20 行访问器 × 93 + clamp 规则；A4b 内消化。
- **C2 步骤接口 vs dt 回调/ROI/分块**：LC 五段固定、无 trait、无 CPU 分块；dt 57 回调 +
  per-module ROI + tiling。调和：不管线照搬；只取三纪律（缓存键含全部输入维、
  窗口渲染、CPU 参考先行 GPU 后孪）。我方 `IopModule` trait（CORE-DESIGN §1）保留。
  代价：无新增；LC pipeline/gpu 代码零复用。
- **C3 图库真相 vs 两处存**：LC catalog 单真相 + 可选 sidecar；dt DB+XMP 双写 + crawler
  四选一；我们 SQLite + XMP 自有命名空间（用户已裁）。调和：SQLite 是我方编辑真相；
  dt 键只读不解析、写回字节保留；冲突用 mtime + 重读合并（PLAN B13 已定）。
  代价：无新增；LC journal 不取。
- **C4 预览/缩略图路径**：LC 三级 + 嵌入优先 + CPU 缩略图；dt mipmap 级 + 磁盘缓存。
  调和：LC 机制全取，档位对 dt 用法（fitted 2560 恰合 Preview 上限，无需调）。
  代价：B15 +2 lane。
- **C5 无自研去马赛克**：LC 拥有解码故 process 覆盖全部观感；我们依赖 rawspeed，
  其升级可漂移观感。调和：process 键折入 rawspeed 版本 + RCD 参数 hash；解码钉版本；
  文档记死。代价：约 30 行（版本折键 + 钉版本断言）+ 2 测（B2 解码版本键 1、B13 缓存键 1），0 lane。
- **C6 命令粒度 vs dt 历史条目**：LC 命令 = 撤销步 = journal op；dt 条目按模块 + 使能位。
  调和：一命令提交一条历史（SetParam 即一条），滑杆拖动 Begin/EndEdit 合并
  （PLAN §2.5 已定），撤销 = history_end 移动 + 落盘。代价：无新增。
- **C7 process 版本 vs modversion**：LC process 是渲染代际；dt modversion 是参数版本
  （迁移链收敛到当前）。调和：两者正交并存——modversion 管参数迁移（读 dt 用），
  process 管我方渲染冻结（写我方用）；读 dt 历史恒按 dt 迁移链解释，不套 process。
  代价：纪律项，B12/B13 各一测钉死。

## §13 Not found（F12 没查到的）

1. F5 三数（347ms / 0.72s / 0.5s）：`grep -rn '347\|0\.72' docs/ crates/`（LC 树）
   无相关命中；`target-app-parity.md` 性能行只有 GPU/库打开数。结论：查不到，
   不沿用；A-10 门待 B15/B16/B20 实测。
2. `export` TABLE 悬空的原因：未查 git 历史（只读源码面；`git log` 可查但非必需，
   fold 进 engine 为推断，有 `export.rs` 存在佐证）。
3. 精确命令数：`grep -c 'cmd!'` = 371 含测试/文档行，未逐一定界；命令级清单未列
   （F2 只需机制，数量非必需）。
4. LC 侧 GPU 等价 `cases()` 31 组中每组阈值余量：未逐组读（门值已得，非必需）。
5. dt 侧：本 lane 无新增 not-found（HISTORY-COMPAT/CORE-DESIGN 已覆盖）。

---

## 附：旧笔记（LIGHTCRAFT-NOTES.md）与现源码对不上处

以本地 HEAD `0da998f2`（= 笔记 §七锚）为准：① 「24 库 + 3 app」→ 实测 29 crate + 3 app。
② 层表：`heif` 笔记/docs 写 L1，`layers.rs:44` 为 L0；新增 `lensdb/fetch/sysmem/faces/
inpaint/geocode/scenes/slideshow` 笔记层表无。③ 缓冲池「≤2GB」→ `DEFAULT_POOL_BYTES=256MB`
（`ctx.rs:208`）。④ 「canary」→ 机制在（`render.rs:747-753`）但全仓无此词。
⑤ 等价用例「26 组」→ `cases()` 31 组（`sed -n '142,434p' … | grep -c '("'`）。
⑥ 笔记 10-25/10-31 节述远端进展，本地树未动——本次结论以本地树为准，远端增量未纳入。

## 附：裁决点（只列真需用户定的）

无。技术取舍已定（§8/§9/§12）。A-10 三门的口径沿 #26，B15/B16/B20 实测后若不达标再报用户。

## 附：复审修订记录（独立 omp，`framework-review.log`，PASS / 0 error + 2 minor）

- minor① T-F11 无分波小时列 → 已加小时列 + 行加总式（A 51.5h 可逐行验算）。
- minor② C5 代价「小」未量化 → 已改为「约 30 行 + 2 测，0 lane」。
