# FRAMEWORK-TABLES — 框架调研长表（正文见 FRAMEWORK.md）

口径：LightCraft 本地树 `/Volumes/UNITEK/Documents/Development/lightcraft`，HEAD `0da998f2`
（`git log --oneline -1`，2026-11-26 实测；与 LIGHTCRAFT-NOTES.md §七的 2026-10-16 锚一致，
§七之后本地无更新）。行数命令：`wc -l <file>`；行内计数：`grep -c <pat> <file>` /
`sed -n 'A,Bp' <file> | grep -c <pat>`。下文 `LC/` = 该树根，`LM/` = Lightamer 仓根。

---

## T-F1 LightCraft 层与 crate 对照（以 `xtask/src/layers.rs:35-71` TABLE 为准）

| 层 | crate（包名去 `lightcraft-` 前缀） | 说明 |
|---|---|---|
| L0 | `geom`, `color`, `raster`, `tiff`, `sysmem`, `fetch`, `heif` | 矩阵/色彩/float 缓冲/TIFF/unsafe 隔离/模型下载/HEIC |
| L1 | `denoise-core`, `denoise`, `raw`, `codecs`, `meta`, `develop`, `inpaint`, `faces`, `geocode`, `scenes`, `slideshow` | 解码/编解码/元数据/编辑模型/AI 降噪/人脸/修补/地理/演示场景/幻灯片 |
| L2 | `lensdb`, `pipeline` | 镜头库、CPU 参考管线 |
| L3 | `gpu`, `catalog`, `preview`, `export`（悬空，见注）, `merge`, `segment` | GPU 孪生/图库/预览缓存/合成/分割 |
| L4 | `engine` | Session + 命令注册表 + 历史 + 作业 + 导入导出 |
| L5 | `ui-egui`, `mcp` | 界面（可换皮）、MCP 服务器 |
| Testkit | `testkit` | 只许 dev-dependency，规则层面视作 L5 |
| Exempt | `lightcraft`, `cli`, `web`, `xtask` | 三 app + 工具，不查 |

注：`crates/` 下无 `export/` 目录（`ls crates/export` = No such file or directory），
根 `Cargo.toml` workspace.dependencies 也无 `lightcraft-export`；导出实现在
`crates/engine/src/export.rs`（3472 行）。TABLE 条目悬空但检查不报错（只查存在边的方向）。

同层允许链 `INTRA_LAYER_ORDER`（`layers.rs:76-85`，下游可用上游，反向违规）：
`[geom,color,raster]`、`[tiff,raster]`、`[denoise-core,denoise]`、`[meta,raw]`、
`[meta,codecs]`、`[meta,develop]`、`[develop,scenes]`、`[codecs,raw]`。
UI 名单 `UI_CRATES`（`:97`）：`craft-ui, egui, eframe, winit, egui_kittest, rfd, bevy*`（`*` 前缀），
`UI_MIN_LAYER = 5`（`:100`）。

违规五类（`Violation`，`layers.rs:139-146`；`check` `:171-218`）：
`Unregistered`（未登记）/ `Upward`（`to >= from`，同层默认也算）/
`StandaloneHasWorkspaceDep`（TABLE 中零使用）/ `TestkitAsNormalDep` / `UiBelowL5`。
数据源 `from_metadata`（`:221-242`）：`cargo metadata --format-version 1 --no-deps` 的直接边，
`workspace = 成员名命中或有 path`；`DepKind`（`:118-123`）分 Normal/Dev/Build 但规则不区分，
只有自身依赖（`:184`）放行。不查：传递依赖、外部版本与 feature、Exempt 的边、悬空 TABLE 条目。

## T-F2 前端入口与分发口

| 前端 | 入口 | 到达分发口的路径 |
|---|---|---|
| UI（egui） | `crates/ui-egui/src/lib.rs:595` `LightcraftApp::run`（注释单入口） | `menus.rs:411 run_ui_command` 未命中 → `:620 session.execute` |
| JSON 控制通道 | `apps/lightcraft/src/control_server.rs:26/40/69/181` 传输 + `crates/ui-egui/src/control.rs:196 handle` 方法 | `handle :201` 分支 `engine.execute\|ui.menu.invoke\|command` → `app.run` |
| CLI | `apps/lightcraft-cli/src/main.rs:520 run` / `:514 run_step` / `:298 mcp` / `:766 snapshot` / `:935 commands` | `Backend::call("engine.execute",…)` |
| MCP | `crates/mcp/src/tools.rs:555 call_tool` / `:428-429 exec` | 同上经 `Backend` trait（`backend.rs:14`）；headless 直调 `session.execute`（`headless.rs:119-124`），connect 经控制通道 |
| headless 快照 | `crates/ui-egui/src/headless.rs`（头注释：与控制通道走同一 handler） | 同 `handle` |
| Web（第六前端） | `apps/lightcraft-web/src/web.rs:587 command` | 下一帧执行 |

引擎分发口：`Session::execute`（`crates/engine/src/lib.rs:512-513`，注释 `THE entry point for every frontend`）、
`execute_fn :531`、`run_command :535`（panic 捕获 + journal + sidecar 自写 + 持久化）、
`commands :580`、`find_command`（`cmd/mod.rs:184`）。
命令声明：`cmd/mod.rs:50-69`（`Run`/`Enabled`/`CommandSpec{id,label,menu,shortcut,params,enabled,run,journal,explicit_targets}`）、
宏 `cmd! :129-134`（默认 `journal:true`，`query` 为 false）、`command_specs :139`。
`grep -c 'cmd!' crates/engine/src/cmd/` = 371（含测试与文档行，非精确命令数；精确数未查）。
历史：`undo:Vec :230`、`redo :234`、`commit(label,op) :587`（上限 1000，清 redo）、
`undo_step :724` / `redo_step :749`（`_with(fs)` 含文件改名回滚）。
作业：`activity.rs`（438 行）：`Activity :21`、`start :173`、`list :198`、`cancel :204`、
`cancel_all :211`、`TaskGuard :223`、`TaskHandle :281`；渲染 `ui-egui/src/render.rs:599 dispatch`；
导出 `engine/src/export.rs:1621 prepare_batch` / `:1967 run_batch(progress->bool)` /
`:1983 export_parallelism`；预览 `cmd/previews.rs:75 task_for`；幻灯片 `cmd/slideshow.rs:324`。
锁：`catalog/src/lock.rs`（162 行）：`LOCK="catalog.lock" :32`、`OWNER :34`、
`LibraryLock :93`、`acquire :102`（`try_lock`，`WouldBlock→InUse`）；加锁点
`engine/src/library.rs:410 open_library` / `:423` / `:394 check_library` / `:684 close_library`。
Connect：`mcp/src/backend.rs`（387 行）：`reconnect :52`、`roundtrip :73`、
`Remote::call :140`（已发出后断线报 unknown outcome 且不重发）。

## T-F3 控制规格与 process 版本

- `CONTROLS`：`crates/develop/src/controls.rs:144`，宏 `:130-169`，行 `:171-292`，
  `sed -n '171,292p' … | grep -c '=>'` = **122**（全文件 `wc -l` = 590）。
- `INDEXED`：`:296`，10 模板（`pointColor.*` 8 + `redEye.*` 2）；`get :149` / `set :157` /
  `find :463` / `split_indexed :410` / `indexed_instances :472`。
- 三消费方：① `ui-egui/src/panels/right.rs:407,597` + `edit.rs:40-41`；
  ② `engine/src/cmd/query.rs:187-203 develop.controls` → `mcp/src/server.rs:41,207,218`
  （`lightcraft://controls`）；③ `develop.set/merge` 等经 `get/set`（`cmd/develop.rs:179-195`）。
- `DevelopSettings`：`develop/src/settings.rs`（1193 行）：`SCHEMA_VERSION=1 :9`（结构版本）、
  `ProcessVersion(pub u32) :23`、`legacy :50`、`is_legacy :56`、`process() :63`、
  字段 `:110`（`default=legacy` + `skip_serializing_if=is_legacy`）。
- `hash64`：`develop/src/lib.rs:59`（FNV-1a over settings JSON）；V1 省略保老 key 不变。
- 预设组：`develop/src/presets.rs`（302 行）：20 个 `SettingsGroup`，`process` 不在任何组。
- 管线分支：`pipeline/src/finish.rs:282`（`match s.process.process()`）、
  `local.rs:273 tone_base_detail`、`local.rs:440 BaseKey=(u32,Process,usize)`。

## T-F4 管线、缓存、GPU、内存

- 管线：`crates/pipeline/src/lib.rs`（740 行）：五段见 `:1-30` 模块文档；
  `render/render_cached/plan/lin_cpu`（`:300-600` 窗口）；`RenderRequest/Rendered/Quality/PixelWindow`（`:1-300`）。
- `StageCache`（`:1-300`）：`capacity=2`，条目 `{src,geo,sampled,lin,planes}`；
  `geo=hash(frame,w,h)`，`pre_nr_key`，`lin_key`（`plan()` 内，`:300-600`）。
- GPU：`crates/gpu/src/render.rs`（1246 行）：`render :580`；`FLUSH_INVOCATIONS=16M :138`；
  `BAND_PIXELS=4M :141`；alpha-255 检查 `:747-753`；全黑复算 `:756-768`。
  `crates/gpu/src/ctx.rs`（743 行）：`MODULES :1-123`；`DEFAULT_POOL_BYTES=256MB :208`；
  复用规则 `:339-503`；`FailKind :612-623`；`ErrorScopes :675-701`。
  回退：`Fallback::{NotTried,Failed}`（`gpu/src/lib.rs:121-136`）；Limit/OOM/Blank 本张 CPU，
  Fatal → `mark_broken` 整进程 CPU。`canary` 全仓 grep = 0 命中（机制在，名字不在）。
- 内存：`crates/sysmem/src/lib.rs`（80 行）：仅 `release_free_memory`。
  `crates/engine/src/memory.rs`（318 行）：`default_budget :25`（RAM/4，钳 256MB–1.5GB，
  `LIGHTCRAFT_MEMORY_MB` 覆盖）；`cache_share :95`（1/2）、`work_gate :176`（1/4）、
  GPU 池 1/8、导出 gate 2×budget（`:183-189`）；`WorkGate+Permit :99-160`；
  调用点 `denoise.rs:902,931-933`、`files.rs:781,1045,1065,1075`、`import.rs:1318`、
  `cmd/denoise.rs:264`；`release hook :263`。

## T-F5 图库与预览缓存

- `crates/catalog/src/journal.rs`（709 行）：`VERSION=9 :79`；快照 `:291`（temp+fsync+rename）；
  日志行 `{seq,crc,op}`；`SnapshotPolicy{2000 条, 16MB}`；后台快照 `:554-709`；
  损坏规则：torn 尾丢弃 / 半批 truncate / 快照覆盖按 seq 跳过 / 好记录后坏记录 → 停播 +
  `catalog.log.damaged-<seq>` + 新快照。
- `store.rs`（269 行）：`FsStore` temp 独占 + fsync + rename + `sync_dir`。`lock.rs` 见 T-F2。
- 提交链：`Session::commit`（`engine/src/lib.rs:587`）→ `pending_log` → 每顶层命令后
  `persist()`（`engine/src/library.rs:609`）一次 append+fsync；`Op::Batch`（`catalog/src/lib.rs:260`）。
- 预览：`crates/engine/src/media.rs`（2297 行）：`SourceLevel{Thumb,Preview,Full} :93`；
  `THUMB_SIZES=[128,256,384,512] :68`；`RENDER_CACHE_VERSION=64 :65`；
  `build_job :1215-1300`（128 位 key：content + settings_hash + bucket + 版本 + 相机）；
  `RenderJob::run_photo :733-1070`；`QuickJob :1085`；`quick_view_job :1517`；
  `set_budget :505`、驱逐 `:531-541`。
- `crates/preview/`：`lib.rs`（248 行，`MAX_QUEUED_BYTES=128MB :34`）、`pool.rs`（359 行，
  per-slot 去重）、`lru.rs`（117 行，`next_tick`）、`disk.rs`（446 行，`.lcthumb`、
  `QUALITY=90 :42`、`STALE=7天 :52`、超预算剪到 80%）。
- 立即做：内存 apply、journal append+fsync、内存 LRU 插入、key 切换。
  延迟做：磁盘 JPEG 编码（后台单线程）、快照 compaction、邻居预取、视口外渲染。
- 三个性能数（347ms / 0.72s / 0.5s）：docs + crates 全文 grep 无命中，**查不到**（见 §13）。

## T-F6 XMP

- `LC_NS`（`meta/src/xmp.rs:18`）；写 `lc:settings/lc:flag/lc:location`
  （`engine/src/sidecar.rs:331-369`，经 `write_xmp_lc` `xmp.rs:572`）。
- `OWNED` 17 项（`sidecar.rs:375`）+ `OWNED_IF_STATED` 4 项（`:398`）；
  合并 `merge_xmp`（`meta/src/xmp_merge.rs:205`，全文件 442 行）、`scan :97`。
- `crs:` 只读：`engine/src/crs.rs:191 to_partial`、`:99 has_adjustments`；
  字面映射约 74 处 + mixer 循环 32 + 2010 回退 7 + WB 组（grep 分段计数）；
  表正本 `docs/xmp-interop.md` Reading `crs:` 节。

## T-F8 取舍清单全表

照搬（8）：分层检查脚本；never-crash lint 属性；testkit skip 模式；sysmem；
LRU 全局 tick；process 版本规则（缺=V1/省略保 key/显式升级）；activity 栈语义；
owned-merge 写回纪律。
改造（11）：命令注册表骨架；`Session::execute` + undo 接线；控制规格单表形态；
JobPool；PreviewCache/DiskCache；WorkGate 配额；export `run_batch` 进度/取消；
`catalog.lock` 语义；GPU 回退阶梯；等价性门数值口径；parity 检查门。
不学（9）：自研 RAW 解码；egui 界面；跨平台解码/色彩底座；op-log journal 持久化；
CPU 全管线函数式形态；`crs:` 近似映射器的内容；LR catalog/Luminar/模板导入；
faces/geocode/slideshow/web； craft-fonts/分发矩阵。

## T-F9 四方映射与新布局

四方映射（LC crate → 我方现计划 crate → dt 概念 → 波次）：

| LC crate | 我方现计划（T2） | dt 概念 | 波次 |
|---|---|---|---|
| geom/color/raster | dt-core（Frame/Roi 部分） | `dt_iop_roi_t`、像素缓冲 | B1 |
| develop（settings+controls） | dt-history（栈）+ A3 panel 描述 | history 栈 + 模块 GUI | A3/B12/B13 |
| develop（process） | （新）dt-history 内 process 字段 + dt-catalog 列 | 无（dt 靠 modversion 迁移） | B13 |
| pipeline | dt-core（调度/缓存/tiling） | `pixelpipe_hb.c` 13 步 | B1/B14 |
| catalog | dt-library | `library.db` + XMP | B13/B15 |
| preview | （新）dt-preview | mipmap/缩略图缓存 | B15 |
| gpu | （新，C 期）dt-gpu | OpenCL 核 | C（B 不做） |
| engine（命令/undo/作业） | dt-api + dt-app + dt-export（fold 进） | `control/jobs` + history 栈操作 | A7a/B16 |
| engine/memory | （新）dt-engine::memory + dt-sysmem | 无 | A7a/B2 |
| sysmem | （新）dt-sysmem | 无 | A7a |
| mcp | （新，C 期）dt-mcp | `src/mcp/` | C-9 |
| ui-egui | dt-gpui | `src/views/` + `src/libs/` + bauhaus | A7b/B17-19 |
| testkit | （新）dt-testkit | 无 | A3R |
| scenes | （新）dt-scenes | 无（测试夹具） | A5/B20 |
| raw/codecs/meta | dt-decode + dt-meta（新） | rawspeed/ImageIO/exiv2 | B2/B12 |
| color（lcms2 部分） | dt-color | `colorspaces.c` | B3/B5 |
| merge/segment/denoise/faces | dt-lightamer（C 期） | 无对应 | C-7/C-9 |
| xtask layers/assets/parity | Scripts/rust-guard.sh + xtask（已建） | 无 | A3R |

新分层布局（名字、层号、允许依赖）：

| 层 | crate | 允许依赖（严格向下 + 同层链） |
|---|---|---|
| L0 | dt-geom, dt-raster, dt-color-math, dt-iop-traits, dt-sysmem | 无工作区依赖（traits 纯类型）；同层链 `[dt-geom, dt-color-math, dt-raster]` |
| L1 | dt-iop-raw, dt-iop-geom, dt-iop-color, dt-iop-display, dt-meta, dt-color, dt-blend, dt-decode, dt-scenes | L0；同层链 `[dt-meta, dt-decode]`（解码读元数据） |
| L2 | dt-registry, dt-history, dt-pipeline | L0/L1；同层链 `[dt-registry, dt-history, dt-pipeline]` |
| L3 | dt-catalog, dt-preview, dt-apple（仅 macOS）, dt-gpu（C 期占位）, dt-merge（C 期占位）, dt-lightamer（C 期占位） | L0–L2 |
| L4 | dt-engine（含 export/memory/import/作业） | L0–L3 |
| L5 | dt-gpui, dt-mcp（C 期占位） | L0–L4 |
| Testkit | dt-testkit | dev-dependency only |
| Exempt | apps/dt-cli, xtask | 不查 |

dt 兼容块落点：模块描述（params 布局/version/migrate/panel）= 各域模块目录（A3 不动）；
顺序 = `fixtures/dt-order-*.json` + dt-registry 计算；参数布局 = 模块内 `repr(C)` + A4b 夹具；
历史读取 = dt-history；blend v15 编解码 = dt-history，栅格化 = dt-blend。
Apple = dt-apple（L3）。gpui 界面 = dt-gpui（L5）。CLI 与对照 = apps/dt-cli（Exempt）+ Scripts。
process 版本：类型与规则 dt-history，存储 dt-catalog 列 + XMP 自有命名空间，命令 dt-engine。
A3 产物搬迁：`ModuleDesc`/trait → dt-iop-traits（L0，不动内容）；4 域目录 → L1（不动）；
顺序计算 → dt-registry（L2）；`fixtures/dt-order-5.7.0.json` 不动；探针测试随 registry 走。

## T-F10 可取用代码

| # | 路径 | 行数 | 做什么 | 取用方式 | NOTICE 写法 |
|---|---|---:|---|---|---|
| 1 | `xtask/src/layers.rs` | 316 | 分层检查引擎 + TABLE + 单测 | 改造：换 TABLE/层号 | 下方 N1 |
| 2 | `crates/testkit/src/lib.rs` | 190 | skip 宏 + JSONL 记录 | 照搬改名 | N1 |
| 3 | `crates/sysmem/src/lib.rs` | 80 | `release_free_memory`，macOS FFI | 照搬 | N1 |
| 4 | `crates/engine/src/memory.rs` | 318 | 预算切分 + WorkGate + release hook | 改造：数值按 16GB 调 | N1 |
| 5 | `crates/preview/src/pool.rs` | 359 | JobPool per-slot 去重/latest-wins | 改造：key 类型换 | N1 |
| 6 | `crates/preview/src/lru.rs` | 117 | 跨缓存 LRU + 全局 tick | 照搬 | N1 |
| 7 | `crates/preview/src/disk.rs` | 446 | 磁盘缩略图缓存布局与配额 | 改造：后缀/编码换 | N1 |
| 8 | `crates/preview/src/lib.rs` | 248 | PreviewCache 内存+磁盘+后台写 | 改造 | N1 |
| 9 | `crates/catalog/src/lock.rs` | 162 | 单写者锁文件 + owner 信息 | 改造：库目录锁 | N1 |
| 10 | `crates/engine/src/activity.rs` | 438 | Activity 栈 + Guard/Handle + 取消 | 改造：kind/label 换 | N1 |
| 11 | `crates/engine/src/cmd/mod.rs` | 225 | CommandSpec + cmd! 宏 + find/dispatch 骨架 | 改造：命令集换 | N1 |
| 12 | `crates/develop/src/settings.rs`（process 段约 `:9-70,:103-120`） | ~80（段） | ProcessVersion 宽容反序列化 + 省略规则 | 改造：随 dt-history 类型 | N1 |
| 13 | `crates/meta/src/xmp_merge.rs` | 442 | owned 合并 + 逐字节保留扫描器 | 改造：待 A4a 选库后决定 port 面 | N1 |
| 14 | `xtask/src/assets.rs` | 136 | 归属门引擎 | 改造：换我们的 LICENSE/ATTRIBUTION 规则 | N1 |
| 15 | `xtask/src/parity.rs` | 520 | checklist 引用门 + 加权统计 | 改造：换 dt parity 清单 | N1 |
| 16 | `crates/gpu/src/render.rs`（回退段 `:580-780` 思路） | — | 回退阶梯结构 | 学设计、自己写 | — |
| 17 | `crates/mcp/src/backend.rs` | 387 | connect 转发 + 不重发语义 | C 期再取，B 不动 | N1（如取） |

N1（`NOTICE` 模板，MIT OR Apache-2.0 任选其一，与 GPL-3.0-or-later 兼容）：
`This product includes software derived from LightCraft (https://github.com/storytold/lightcraft,
commit 0da998f2), Copyright (c) 2026 ArtCraft Team and the LightCraft contributors,
licensed under the MIT License or the Apache License, Version 2.0, at your option.
Derived files: <我方路径> <- <LC 路径> (<原样|改造说明>).`
LC 文件无独立许可头（工作区级许可），逐文件加 `// Derived from lightcraft <path>` 注释即可。
注意 LC 的 clean-room 反向约束：它禁读 GPL（darktable/rawspeed/lensfun），我们取用它的代码
不受此限，但不要把它的相机矩阵/色彩拟合数据当真相（那是估计值，非测量值）。

## T-F11 波次影响

阶段 A 新波次表（10 波，20 lane，51.5h；原 9 波 17 lane 43.5h）：

| 波 | 内容变化 | lane | 小时 |
|---|---|---:|---:|
| A1 | 不变 | 1 | 2 |
| A2 | 微调：空壳按 T-F9 新布局建（含占位 crate 的空壳与改名） | 2 | 4 |
| A3 | 不变（产物与 crate 摆法无关） | 3 | 7.5 |
| **A3R（新）** | 重排：改名（dt-core→dt-pipeline、dt-library→dt-catalog）+ fold（dt-api/dt-app/dt-export 进 dt-engine 规划）+ 分层检查（T-F10#1 落地、`cargo xtask layers` 进 guard）+ dt-testkit 落地 | 2 | 5 |
| A4a | 不变（T-F10#13 的 port 面待选库后定） | 1 | 3 |
| A4b | 不变，crate 指向 dt-history（L2） | 3 | 9 |
| A5 | 不变（+dt-scenes 规划输入） | 2 | 5 |
| A6 | 不变，crate 指向 dt-apple（L3） | 1 | 2 |
| A7a | **重做**：命令分发口（registry + `Session::execute` + undo + activity + memory/WorkGate + headless + CLI run 路径 + 5 条 headless 测试改述） | 3（+1） | 8（+3） |
| A7b | 不变 | 2 | 6 |
行加总：2+4+7.5+3+9+5+2+8+6 = **51.5h**（原 43.5h：A7a 原 5h；增量 = A3R 5h + A7a 3h = 8h）。
阶段 B 每卡（20 波，80 lane；原 76 lane）：

| 波 | 落点 crate | 内容变化 |
|---|---|---|
| B1 | dt-pipeline（L2） | 不变；缓存键预留 process 维（空位不断言） |
| B2 | dt-decode（L1） | 不变；解码前后调 release hook、后台解码走 work_gate（A7a 已供能力，B2 只接线） |
| B3–B11 | 四域（L1） | 不变 |
| B12 | dt-history（L2） | 不变 |
| B13 | dt-history + dt-catalog（L3）+ dt-engine | **+process 版本列/升级命令/owned-merge 写回**（+1 lane） |
| B14 | dt-blend（L1）+ dt-pipeline | 不变 |
| B15 | dt-catalog + dt-preview（新，L3）+ dt-engine | **+PreviewCache/DiskCache/JobPool + embedded-first + 邻居预取**（+2） |
| B16 | dt-engine::export | **+activity 进度/取消 + 导出 gate**（+1） |
| B17–B19 | dt-gpui（L5） | 不变（经 engine 命令；桌面控制通道延期到 C 随 MCP） |
| B20 | — | 不变 + A-10 三门（0.72s/1s/0.5s）+ process 漂移检查 |

估时：A +3 lane（A3R 2 + A7a 1），B +4 lane（B13 1 + B15 2 + B16 1），合计 93→**100 lane**；
墙钟 251.5h→**271.5h**（×1.2 含自审 ≈326h ≈ 41 个 8h 日）。减项：无（空壳 fold 不省 lane）。
