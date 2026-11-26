# ARCHITECTURE — 会话架构定稿调研（只读 lane）

> 日期 2026-11-26。输入：PLAN-AMENDMENTS.md（A-1..A-14）、FRAMEWORK.md（LC 树 `0da998f2`）、PLAN.md §0–§2、HISTORY-COMPAT.md、九月调研（FEATURES/ARCHITECTURE/SUMMARY）。长表见 `ARCHITECTURE-TABLES.md`（T-A*）。结论先行、证据随后；无实测标「推断」，官方未写标「官方未说明」。

## §0 One page（45 行）

```text
会话包（plain 文件夹，可整包拷走）：
<Name>/  Capture/  Selects/  Output/  Trash/  <Name>.lmsessiondb(SQLite)  Cache/Thumbs/  session.lock
每张图：<图> + 同目录 Lightamer/<stem>.lmsettings（JSON 调整+元数据，随图走）
应用层：~/Library/Application Support/<App>/{RecentSessions,Templates,prefs}（会话之外）
```

| 层 | 内容 |
|---|---|
| L2 dt-history | 历史栈+设置文件编解码+process 版本 |
| L3 dt-catalog/dt-preview | 会话 SQLite（结构+索引）/会话内缩略图 |
| L4 dt-engine | 会话命令+锁+作业+导出（默认落 Output/） |
| L5 dt-gpui | 会话浏览器+灯箱+暗房（面板由描述生成） |

用户问题的答案：**历史存在每张图的设置文件里，不在库里**（库只存结构/索引/缓存）；**XMP 第 0 期不要**（不选库、不写；元数据随设置文件走，导出嵌入标准字段；跨软件 XMP 互通排 C 期）。
导入默认复制进 Capture/（可选原地引用）；Selects=物理移动；删除=移进 Trash（只读），清空=永久删除，撤回=移回；最近 10 会话存应用层；模板=相册/收藏结构；多会话=多窗口各持一会话，同一会话单写者锁。
要用户定的 5 件（§8）：①历史位（推荐设置文件）；②库存储（推荐 SQLite）；③导入默认复制（推荐复制）；④要不要目录模式（推荐不做）；⑤单张可否带调整搬出（推荐可以）。
新估时：**A 9 波 18 lane 45.5h；B 20 波 79 lane 217h；合计 97 lane 262.5h（含自审 ≈315h ≈40 日）**。首个可用版仍 B20 后。

---

## §1 Q1 — Capture One 会话模型（证据全表 T-A1；九月勘误 T-A2）

**文件夹结构**：新建会话得顶层文件夹，内含 `Capture/ Selects/ Output/ Trash/` + `<Name>.cosessiondb`（T-A1 #1、#3、#5）。四文件夹可改名、可移位、可重指定到任意收藏文件夹（#55）。

**数据库里有什么**：Session Favorites 和 Albums（#6）；会话数据库没有目录那样庞大的库（#39 引文 "does not have the same extensive database of a Catalog"）。调整不在库里（#7）。

**调整存在哪**：图片所在文件夹的 `CaptureOne`（新版 `SettingsNNN`，如 `Settings165`）子文件夹，每张图 `.cos` 设置文件（#8、#9、#10）。RAW 永不改（#52）。

**四文件夹用途**：Capture=联机落点+导入默认目的地（#14、#49）；Selects=物理移动 keeper（#17，Cmd+J；不想搬用相册 #19）；Output=全部处理的落点（#15）；Trash=删除=移入暂存，只读（#20、#22），清空=永久删除不可撤回（#21），撤回=拖回（#23）。

**拖拽与浏览**：不导入可直接浏览现有文件夹，浏览即建缓存与设置文件（#11、#12）；整包按相对结构搬运则完整，无需数据库文件（#7、#13、#33）。单张图跨文件夹拖拽时设置是否跟走：官方未说明（T-A9 #3）。

**模板**：存相册+收藏结构（+Next Capture 命名），不存图片（#28）；File > Save As Template 制作（#29）。

**会话 vs 目录**：会话=短单/联机/自包含文件夹（#45）；目录=大库/跨拍搜索/集中库（#44），调整在库内（#42），分 managed/referenced（#43）；会话可整体并入目录（#46）。

**多会话/最近/备份/删除/变体**：多会话=偏好开新窗口后 File > Open Session，可跨会话拖文件（#30）；同一会话开两次官方未说明（T-A9 #2）；Open Recent 记 10 个（#32）；会话无自动备份，手动整包拷（#35、#36；Trash/Cache 可略）；删会话=OS 删文件夹，连原图一起没（#34）；升级只动数据库并自动留 `.cosessiondb.backup`（#37、#38）；校验=File > Verify（#39）；变体=源文件+settings BLOB 的虚拟表示，可多份、可跨相册存在（#40、#41）。

**导入**：导入对话框只用于外部介质（#47）；本地盘用导入=复制出重份，不推荐（#48）；导入可顺手备份/命名/版权/套样式（导入指南节）；EIP 打包（调整+变体+ICC/LCC）随 Include Existing Adjustments 生效（#50）。

**XMP**：只管元数据同步（Full Sync 双向/Load 单向/None + 手动），调整不走 XMP（#51）。

**九月笔记勘误**（T-A2）：①`Captures`→`Capture`（以 2025 支持文档为准；2017 博客写 Captures）；②`Crop/` 无此官方文件夹；③"设置在 Capture 子文件夹"不准，应为每张图所在文件夹之设置子文件夹；④".cosessiondb 非真相"半对（收藏/相册的真相就在它里面）；⑤四文件夹可重指定成立且含 Selects；⑥ Session-vs-Catalog 表基本成立（"目录底层 SQLite"系笔记推断）。

## §2 Q2 — 我们的会话包

**磁盘形态**（plain 文件夹，C1 同款，不做 macOS 包——跨平台拷不丢 bundle 位）：

```text
<Name>/
├── Capture/                 # 导入默认落点（复制），联机落点（D-2）
├── Selects/                 # Move to Selects 物理移动目的地
├── Output/                  # 导出默认落点
├── Trash/                   # 删除=移入（库内标记只读），清空=永久删除
├── <Name>.lmsessiondb       # SQLite（结构+索引+缓存键；调整不在此）
├── Cache/Thumbs/            # 磁盘缩略图（内容键，可重建，备份可略）
├── session.lock + .owner    # 单写者锁（LC lock.rs 语义，T-A6）
└── Lightamer/               # 顶层设置文件夹只用于直接放根的图片；各子文件夹图片各有自己的
    └── <stem>.lmsettings     #   （规则：设置文件恒在"图所在目录"的 Lightamer/ 下）
```

**设置文件规则**：每张图一份 `<stem>.lmsettings`（JSON：历史栈+元数据+process 版本），放在图所在目录的 `Lightamer/` 子文件夹（C1 `CaptureOne/`/`SettingsNNN` 同款，T-A1 #8）。同名不同扩展（NEF+JPG）共 stem 时：RAW 优先用 `<stem>.lmsettings`，另一份用 `<file>.lmsettings`（LC sidecar.rs:15-18 同款规则）。

**Capture（导入）**：默认=复制进 Capture/（C1 #49 同款；外部介质唯一正路）；备选=原地引用（C1 #48 的"本地盘别用导入" scenario）：实现为库记录指向外部路径 + 自动收藏该文件夹（C1 Favorite 语义 #25）。后果：复制=自包含、备份简单、占双倍空间；引用=零拷贝、图被外移即失联（需重链接命令）。默认复制，引用为导入对话框显式选项。

**Selects**：物理移动图+设置文件（C1 #17 同款，Cmd+J）；不想搬→建相册并设为 Selects Collection（C1 #19 同款，C 期可做，B 期只做物理移动）。

**Trash**：删除=移进 Trash（图+设置文件，库记原路径，浏览面只读，C1 #20、#22 同款）；清空 Trash=永久删除源文件+设置（不可撤回，#21）；撤回=移回原路径（#23）。第 0 期只手动清空（自动清空官方未说明，T-A9 #6）。
裁决点：设置子文件夹名定 `Lightamer/`（可见，C1 同款，不跟 `SettingsNNN` 版本号）；引用模式进第 0 期（导入对话框一个选项，B15 内已含，T-A7）。
**Output**：导出默认落点（#15 同款），配方可改；备份清单含 Output（#36 同款）。

**打开已有文件夹**："Open Folder as Session"：就地生成 `<Folder>.lmsessiondb`+四文件夹（缺的建空）+锁，不搬任何图；已有图按引用建库记录（C1 #11 同款零导入）。另支持"新建空会话+收藏外部文件夹"（C1 Favorite #25 同款）。

**最近会话**：应用层 `~/Library/Application Support/<App>/RecentSessions.json`（最多 10 条，#32 同款）+ File > Open Recent；模板库 `Templates/`（结构 JSON，不含图，#28 同款）；偏好同目录。均在会话之外。

**多会话**：多窗口各持一引擎实例一会话（T-A6）；同一会话第二次打开被 `session.lock` 拒绝并提示持有人（LC lock.rs:19-21 同款；C1 官方未说明，T-A9 #2，故为自有设计）。

**备份/恢复**：命令 `session.backup`=整包拷（Cache 可略，Trash 可选略，#36 同款）；升级库版本前自动留 `.backup`（#38 同款）；恢复=拷回+双击库文件（备份指南同款）。校验=`session.verify`（SQLite integrity_check + 孤儿扫描，#39 同款）。

裁决点：设置子文件夹名（定 `Lightamer/`，可见，C1 同款）、引用模式是否进第 0 期（推荐进，导入对话框一个选项+B15 半 lane，已含在 T-A7 B15 内）。

## §3 Q3 — 修改历史存在哪（用户问题的正面回答）

**三家做法**（证据 T-A3）：C1 会话=设置文件（库只结构），目录=库内；LC=图库单真相（内存 Photo.develop+history 全快照，journal 落盘，XMP 可选）；dt=DB+XMP 双写+crawler 人工裁决。

**三选项比较**（矩阵 T-A4）：甲只存 DB（最省、粘贴最快、但拷图丢调整、库坏全丢）；乙设置文件+DB 索引（C1 会话同款，搬运/备份/波及面最优，批量粘贴需"DB 队列+后台刷文件"追性能）；丙两处都存（互为备份但需裁决器，成本最高，LC/dt 教训均不取）。

**推荐乙**。设计要点：①设置文件=调整真相（JSON：历史栈全条目+元数据+process）；②DB 存索引（评分/关键词/相机/路径）、缓存键、收藏/相册结构；③批量粘贴=DB 队列先行（单事务，UI 立即可见）+ 后台 worker 刷设置文件（tmp+fsync+rename 逐个原子）+ 崩溃重启续刷；④单张搬运=拷图+设置文件（零命令，C1 #7 同款）+ `adjustments.export/import` 命令做跨机旁路；⑤库坏可从设置文件重建索引（`session.verify --rebuild`）；⑥设置文件坏=该图回默认+报错，不碰他图。

**放弃了什么**：①甲的极致粘贴速度（弥补：DB 队列+后台刷，B13 实测，门=1 万张可见提交 1s，A-10）；②丙的双保险（弥补：库可重建+备份整包）；③与 dt/LR/C1 的调整互通（A-12 已裁不要）。

**XMP 还要不要：不要。** 第 0 期不选 XMP 库（A4a 取消）、不写 XMP：A-12 后无 dt 互通义务；C1 实证"调整不走 XMP"（#51）；LC 实证"sidecar 可选"（T-A3）。元数据存设置文件+DB 索引；导出嵌入标准 EXIF/IPTC（手写，不依赖 XMP 库）。跨软件元数据互通（他家读我们的星级）排 C 期"标准 XMP sidecar（只元数据）"，复用 LC owned-merge（T-F10 #13）。

## §4 Q4 — 会话数据库用什么存

**推荐 SQLite（WAL）**，单会话单库文件 `<Name>.lmsessiondb`。比较矩阵 T-A5，要点：①批量=单事务万行（推断毫秒~百毫秒，B12' 实测）；②崩溃=事务+WAL 标准语义；③锁=文件锁+SQLite 锁双保险；④备份=checkpoint 后拷单文件（`VACUUM INTO` 产快照）；⑤智能相册=SQL 多维过滤+索引（LC journal 侧要自写全表扫描，10 万张下是短板，推断）；⑥体积=行存紧凑（LC 全量 JSON 快照+200 步 history 在 10 万张下推断 GB 级）；⑦成本=rusqlite+bundled SQLite（公有领域，GPL 可用），B12' 4 lane 含 schema+迁移（`PRAGMA user_version`）+DAO；⑧测试=SQL 断言+崩溃注入+integrity_check；⑨搬运=随包走（#33 同款）。

**不取 LC journal**：与 FRAMEWORK.md F5 结论一致（"持久化不学，SQLite 代差已定"），A-12 后更无理由重造查询面。LC 可复用的是锁语义、Op/Batch/undo 内存骨架、hash64/process 规则（T-A6）。"结合"方案无收益（SQLite 已给崩溃安全，日志层只加成本）。

## §5 Q5 — LightCraft 落到每会话一库（落点表 T-A6）

LC 引擎一次一库，多会话=多引擎实例（每窗口一 Session），代码按会话复用天然成立：库记录→会话 SQLite（journal 文件对不取）；锁→会话根 `session.lock`（改造 T-F10 #9）；磁盘缩略图→会话 `Cache/Thumbs/`（改造 #7）；内存预览/LRU/JobPool→每实例一份（#5、#6、#8）；**缓存键不带会话标识**（目录已隔离，键 LC 原样：内容+设置hash+尺寸+版本）；compaction→SQLite checkpoint/VACUUM；内存预算→每实例一份+全局上限（改造 #4）；命令/undo/activity→每实例（改造 #10、#11，命令集按 T-A8 重写）；process/hash64→设置文件字段+键维（改造 #12）；最近/模板/偏好→应用层（LC 无对应，自写）；XMP merge→C 期（#13 延期）。

## §6 Q6 — 完整架构

**分层（沿用 T-F9，落点）**：L0/L1（几何/栅格/iop 四域/解码/色彩/混合）不变；L2 dt-registry/dt-history（历史栈+设置文件编解码+process）/dt-pipeline；L3 dt-catalog（会话 SQLite+收藏/相册/检索）/dt-preview（会话缓存）/dt-apple；L4 dt-engine（会话命令 T-A8+锁+作业+导出）；L5 dt-gpui（会话浏览器+灯箱+暗房）+ dt-mcp 占位。会话不增 crate（A2 不变，T-A7）。

**流程**（命令口径，清单 T-A8）：新建=`session.new`（建四件+库+锁）；导入=`library.import`（复制默认/引用可选+库记录+缩略图任务）；浏览=库查询+三级预览（嵌入占位→内存→磁盘→渲染，F5 机制）；进暗房=读设置文件建栈+FULL 管线；编辑=`develop.set`（begin/end_interaction 合并）→设置文件+DB 键+历史步；批量粘贴=单 Batch（DB 队列先行+后台刷文件）；Selects/Trash/Output=`photo.moveToSelects/photo.delete/trash.empty/export.process`（物理移动语义 §2）；备份=`session.backup` 整包拷；重开=`session.open`（锁+载库+失联检测+续刷队列）。

**首见面**：有最近会话→ Recent 窗口（C1 目录指南 "Open Capture One while holding Option… Recents window" 同款）+ 空会话浏览器；无会话→欢迎面（新建/打开文件夹为会话/打开最近，无最近则三按钮中最近置灰）。无"默认空库"——一切照片操作恒在一会话内。

**应用层状态**：RecentSessions/Templates/prefs 在 `~/Library/Application Support/<App>/`（§2），会话之外。

## §7 Q7 — 对计划的影响（逐波表 T-A7）

A4a 取消（-1 lane）；A4b 重做=自有历史模型（3→2）；A5 微调（手写 dt XMP 夹具，lane 不变）；B12 替换=会话包与库 B12'（3→4）；B13 重做=设置文件写（4→3）；B14 退回基础（5→2，余部入 C-6）；B15 加会话行为（6→7，含 EXIF 直读）；B16 微调（默认 Output）；B19 加会话浏览器（4→5）；B20 验收改走会话；其余不动。**新合计 97 lane 262.5h（含自审 ≈315h ≈40 日）**，比 T-F11 少 3 lane 9h。

首个可用版仍 **B20 后**（导入→会话浏览→暗房→导出到 Output→备份恢复闭环，21 模块对 dt 官方版通过）；B16 后无界面全链闭环（含会话 CLI）；B12' 后会话 CLI 可用（建/开/导入/验/备）。

C/D：C-4 减负（智能相册基础已在 B 期）减约 1 波；C-5 加标准 XMP sidecar 约 1 波；C-6 接收 B14 退回约 1 波；dt 历史读挂 C-9 名下不排期（#34）。

## §8 Q8 — 要用户定的事（5 件）

1. **历史位**：甲只存库 / 乙设置文件+库索引（推荐）/ 丙双存。推荐乙：C1 会话实证、搬运备份波及面最优；代价=批量粘贴后台刷（B13 实测补数）。依据 T-A4。
2. **库存储**：SQLite（推荐）/ LC journal / 结合。推荐 SQLite：查询/体积/测试/备份全优；journal 只在"零依赖洁癖"下成立，但 bunded SQLite 无系统依赖，洁癖不成立。依据 T-A5。
3. **导入默认**：复制进 Capture（推荐）/ 原地引用。推荐复制：C1 默认（#49）、自包含、备份简单；引用为显式选项保留（C1 #48 scenario）。依据 §2。
4. **目录模式**：不做（推荐，第 0 期只有会话）/ 做（大库跨会话检索）。推荐不做：用户裁决只要会话（A-14）；多会话+收藏+智能相册覆盖 90% 目录诉求；目录=新真相层，C 期再议。依据 T-A1 #44–#46。
5. **单张带调整搬出**：可以（推荐：拷图+设置文件即走）/ 不可以（锁库内）。推荐可以：C1 同款（#7、#13）、EIP 同款（#50）；代价=设置文件格式稳定承诺（schema 版号+迁移）。依据 §3。

## §9 Q9 — 没查到的与风险

没查到的 10 项见 T-A9（含版本差异 1 项：Output 排除浏览；官方未说明 4 项：同会话双开、单图拖拽跟走、.cos 格式、Trash 自动行为；未实测 2 项：SQLite 批量数、LC 三性能数沿用 FRAMEWORK §13）。

风险（按影响）：R1 设置文件与 DB 索引 skew（缓解：DB 队列单写者+续刷+verify 重建；B13 崩溃注入钉）；R2 引用模式外移失联（缓解：重链接命令+失联标记，B15）；R3 10 万行智能相册性能未实测（缓解：B12' bench，索引先行）；R4 多窗口内存预算叠加（缓解：全局上限钳，B15）；R5 gpui 底座（PLAN R3 沿用，不变）；R6 设置格式稳定承诺（缓解：schema 版号+迁移链，A4b 内）。

---

## 附：FRAMEWORK.md 按 A-12 的重理解（任务书指定）

- C1「以整块参数为真相」→ 改为「以设置文件的版本化 JSON 参数为真相」；blob/hex/modversion 一整套作废；A3 Control 描述的 `offset/size` 访问器改为 JSON path 访问器（A3 不返工：描述结构不动，访问器实现换）。
- C7「modversion 管参数迁移 + process 管渲染冻结」→ 只剩 process 一维（LC 原样）；读 dt 迁移链整段删除。
- A4b lane（3 lane dt 布局链）→ 2 lane 自有历史模型（T-A7）。
- 其余（分层/命令/预览/锁/process 规则）不受 A-12 影响，维持。

## 附：复审记录

- lane 的独立复审实例没有产出（`architecture-review.log` 里只有 `Working...`），所以这份文档没有经过独立复审。塔台的核验记录在同目录 `VERIFY.md` 的 §8：五处官方引文、三处 LightCraft 代码位置和 lane 加总都核过；历史存放这一件，塔台的意见与本文的推荐不同，已在呈报里写明。
