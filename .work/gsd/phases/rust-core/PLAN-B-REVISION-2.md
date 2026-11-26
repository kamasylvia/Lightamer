DONE / 5 文件全改 + 0 处没改

# PLAN-B 修订 2（2026-11-26 下午裁决落定，omp 修订 lane）

只改计划与调研文件，不写代码，不构建，不动 git（除只读 `git status`/`git diff` 自核）。

## 新旧合计对照

| 版 | lane / h | 说明 |
|---|---|---|
| 原计划（`PLAN.md` §3） | 76 / 208 | 基准 |
| ARCH T-A7（乙） | 79 / 217 | 会话乙方案 |
| 签字版（甲，今晨） | 81 / 223 | 含自审 ×1.2 ≈ 268 h ≈ 34 个 8h 日 |
| 本次修订 | **102 / 286** | 含自审 ×1.2 ≈ 343 h ≈ 43 个 8h 日 |

相对签字版 +21 lane / +63 h：`Output/`（B15）+1/+3、B14 由 2 lane 扩为 10 lane（+8/+24）、B14A 新开 +12/+36。相对原计划 +26/+78 h。

逐卡加总验算：lane 3+2+6+4+5+3+4+4+3+3+6+4+4+10+12+8+4+5+4+5+3=102；小时 9+6+12+12+15+6+10+12+6+9+12+12+12+30+36+24+12+15+12+15+9=286。与 §0 一致。

## 改了哪里、改成了什么

### PLAN-B.md

| 哪里 | 改成什么 |
|---|---|
| 文件开头（第 2 行） | 加 crate 名说明：新名 `lightamer-X`/`lightamer-ai`，旧名在研究与核验日志，不改名三项 |
| 全文 crate 名（约 45 行） | `dt-X` → `lightamer-X`；`dt-core` → `lightamer-core`；保留 `dt-master`、`dt_pipe_is_full`、`dt token`/`dt accels`（darktable 简称）、`demosaic.c` 等源码名 |
| §0 表清单 photos 行 | 加导出产物标记（A-18，见 §1.1） |
| §0 合计两行 | 21 波 102 lane / 286 h，自审 ≈343 h ≈43 个 8h 日，写明三处增减 |
| §1.1 新增两条 | 登记（作业完成时写 `photos` 行 + `is_export`，列由 B12′ 建）；显示与派生物规则（一起显示、「显示导出」开关默认开、可浏览预览打开访达显示、三拒绝带原因错误） |
| §1.3 一行 | `约 300–500 B` → `300–500 B（估算）`（消 `约 30` 字面残留，语义不变） |
| §3 标题 | 20 波 81 lane → 21 波 102 lane |
| B14 整卡 | 换成基础包：引言（Q1 来源 + 两处评审改正 + 纪律：调参走 `develop.set`，光栅化/混合/推理在渲染作业内）+ B14-0（2×3，原卡）/ B14-1（4×3，四形状 + 经典组 5 算子含 sum + Lab L 验证链）/ B14-2（2×3，12 混合 L1 + 编解码 L2，余下 24，dt 现行 36）/ B14-3（2×3，折键 + ROI/tiling + 预览 + 失效）；每小卡有汇报；合计 10×3=30 h |
| B14A 新卡（紧跟 B14） | 12×3=36 h：ort+Provider（`lightamer-ai` L3）/ Apple 侧（`lightamer-apple` L3）/ 引擎接线（L4，无 L3 边，T-F9 不动）/ 细化（L1）；四类 + 点选（123 MB）+ 细化 + 风光/深度（塔台理解）+ yakhyo（m1/m2 准确说法）+ Vision 回落 + 身体（Vision 先行，RVM 可选）；身体细分不做 + 四理由；权重不进 git（sha256 锁 + 首用下载 + NOTICE/审计分开登记）；lane 切分 2/4/2/1/1/1/1 |
| B15 范围/验收/估时/任务书 | 加导出产物浏览（`is_export` + 开关数据面 + 三拒绝）；验收 ⑨；8×3=24 h，lane 切分加导出产物 1；验收八条→九条 |
| B16 产出 | 加一句：作业完成时登记产物（`photos` 行 + 标记，列由 B12′ 建） |
| B18 范围 | `本波唯一的 dt-apple 增量` → `本波增量见 §3.1`（B14A 后唯一不成立） |
| B19 范围 | 加灯箱「显示导出」开关（默认开，读 B15 数据面） |
| §3.1 | 标题改名；空壳加 `lightamer-ai`（占位改名非新增）；依赖加 `ort`（B14A，MIT，随包分发见卡，权重不进 git）；apple 增量改为 B14A+B18 两处，其余波零改动 |
| §3.2 | 改标题；加 B14A 命令行（`mask.generate` 新登记 + `develop.set` 调参 + 快照存引用 + 读 B1–B11） |
| §4 引言 + 第 1 条 | 第 1 条已定：进（A-18，与推荐相反），语义见 §1.1，B15 +1 lane 已计入 |
| §4.1 T-A9 #1 行 | 未解决→已定：进，B15 +1 lane |
| §5 一句话 | 加基础包/B14A/Output 三项 |
| §5 B14/B15/B16/B19 行 | 按新范围改写；B1/B18 行改名 |
| §5 B14A 行（新增） | 无→AI 蒙版 12/36 h，依据 A-18 + 蒙版调研，注风光/深度为塔台理解 |
| §5 估时对比 | 签字版→本次四版对照 + 三处增减 |
| §7 末行 | 仅改名 → `lightamer-apple`，内容不动（dated 记录，见下） |

### PLAN-B-TABLES.md

| 哪里 | 改成什么 |
|---|---|
| 文件开头（第 2 行） | 同 PLAN-B.md 的 crate 名说明 |
| T-B1 photos 表 | 加 `is_export INTEGER NOT NULL DEFAULT 0`（A-18）；索引注记加 `is_export`（暂无索引，等 B15 实测） |
| T-B2 头 | 补入 2 条→3 条（加 `mask.generate`，B14A 登记） |
| T-B2 表 | 加 `mask.generate` → B14A 行（作业启动语义）；41 条命令每条恰一波 |
| T-B2 尾两行 | 零新命令波：B14 改形状/组合/混合走 `develop.set`，加 B14A 登记一句；`dt-cli` → `lightamer-cli` |
| T-B3 头 | 加签字版 81/223，新计划 102/286 |
| T-B3 B14/B15/合计行 | B14 10×3=30（+5/+15）；B15 8×3=24（+4/+12）；合计 102/286（+26/+78，自审 343/43d） |
| T-B3 B14A 行（新增） | —→12×3=36（+12/+36），注塔台理解 |
| T-B3 尾两行 | 四版估时 + 相对签字版三处增减 |
| T-B5 标题 + 两行（新增） | 共 12 门；AI 单类 ≤3 s/张、点选 ≤2 s/点，B14A 首测 B20 复量，均标推断 |
| T-B6 标题/表头/B14A 行 | 改名；加 B14A 行（Vision 执行 + Apple 提供者，`macos.rs` 内，能力表只加平台事实） |

### masks-research/RESEARCH.md（E1+M1–M13）

E1（§2.2 引文改 `scripts/ai_models/ai_mask_model_set_v1_NOTICE.txt:48-60`）；M1（§1.4/§0/Q1 三处 `~30`→36，顺延 `~18`→24）；M2 在 TABLES；M3（§1.5 写侧全名）；M4（§1.5 读写双路径）；M5（7 个 rpc + 5 组语义）；M6（§4.4 全路径 `crates/gpu/src/render.rs:1679`）；M7（§4.3 `:160-198`）；M8（§3.6 补 `app.py:1055`；评审写 T-M1b，实为此处）；M9（§4.1 13 变体）；M10（§0 与 B14-1 补 sum，入 B14-1；Q1 理由行四算子→五算子连带）；M11（B14-2 编解码进 `dt-history` L2 + 纪律检查补 L2；研究文件保留旧 crate 名）；M12（§5 上限 `:198/:200` + 全段补路径前缀）；M13（Q4 补 `gtk.h`）；§8 追加评审回注段。

### masks-research/RESEARCH-TABLES.md

E1（T-M5 改正确路径 `:48-60/80-90`）；M1（T-M1a 36）；M2（3085/538）；M3（T-M4 写侧全名）；M4（T-M4 exif.cc 读写双路径；评审写 T-M1a，实为此处）；M6（T-M4 补 render.rs 行）；M7（T-M1g `:160-198` 连带）；M9（T-M4 13 变体连带）；M12（T-M1c 三行补前缀 + `:198/:200`）。

### masks-research/SKIN-FACE-BODY.md（m1–m14）

m1（§2.1 zllrunning 行补 derived data 注 + §3.1 + §4-1 改准确说法"协议未明确提及权重，留解释空间，非商业下风险低（解读）"）；m2（§0 标"权重无单独许可声明"）；m3（53）；m4（`:16-21`）；m5（补 `VNDetectFaceLandmarksRequest.h`）；m6（6 组真名）；m7（换 `VNObservation.h:789`）；m8（末提交安全更新 #21）；m9（§2.1/§3.3 + §0 连带改"README 未明写"）；m10（MODNet 托管未亲证）；m11（§2.1 + §2.2 补 HF 镜像 URL）；m12（Pixel 8a CPU 数未亲证）；m13（两 issue 标同系类比）；m14（session 号待核）；末尾加 §5 修订记录。

## 自己核（命令与输出）

工作目录 `/Volumes/UNITEK/Documents/Development/Lightamer`。

1. `grep -n 'dt-[a-z0-9*]\+' PLAN-B.md PLAN-B-TABLES.md` → 仅 3 命中：两文件开头说明行的 `dt-order-679d594f5d.json`（允许）+ B1 卡 `dt-master`（允许）。无 `dt-` 开头 crate 名残留。
2. `grep -c 'lightamer-ai' PLAN-B.md PLAN-B-TABLES.md` → 5 / 1。
3. `grep -c '^#### ' PLAN-B.md` → 21（B1–B20 + B14A；B14 四小卡为 `#####`，不计入）。
4. 逐卡加总 → 102 lane / 286 h，与 §0 一致（见上表）。
5. T-B2：41 条命令行，`uniq -c` 非一次行数 = 0；`mask.generate` 恰属 B14A。
6. `grep -c '不进图库浏览' / '约 30'` 两文件 → 全 0（`约 300–500` 已改写消歧，`~30 MB` 与 `30 h` 非 `约 30` 字面）。
7. `grep -c '`NOTICE.txt:48'` RESEARCH 两文件 → 0/0；`ai_mask_model_set_v1_NOTICE` → 2/2（含 §8/T-M4 既有引用）；`union/intersection/difference/exclusion/sum` 在 PLAN-B B14-1、RESEARCH §0/B14-1 共 3 处。
8. `git status --porcelain -- <5 文件>` → `M PLAN-B.md`、`M PLAN-B-TABLES.md`、`?? RESEARCH.md`、`?? RESEARCH-TABLES.md`、`?? SKIN-FACE-BODY.md`（后三者系蒙版 lane 未提交的新文件，非我新建）。其余改动（Cargo.lock、Scripts、crates/dt-apple、docs 等）属别的 lane，未动。

## 裁决与证据对不上的单列

1. 调研 Q1 称 B14-2 编解码"读 dt 用"，与 A-12（读 dt 历史非强制需求）冲突。照改，但在 B14-2 产出写成"与 dt blend v15 的映射只用于 oracle 夹具生成，不读用户数据"。理由：A-12 已裁，字面"读 dt 用"无落点；最贴近原意的就是 oracle 夹具生成。
2. `review.log` M4/M8 的位置标注与文件实际不符：M4 写 T-M1a（该表无 XMP 行），实为 T-M4 exif.cc 行；M8 写 T-M1b（该表无该行），实为 RESEARCH.md §3.6。均按实际位置修，§8 修订记录注明。
3. §6 自审表第 1 行（B15"卡面已是 7 lane"）与 §7 认下事项（Output 按推荐不进、Apple 只在 B18 用一次）现与正文不一致。未改：二者是署名 dated 记录；§7 只做了改名。是否同步需塔台另裁。
4. T-B1 加 `is_export` 列：任务只点名 T-B2/T-B3/§0/§5，但"导出产物标记"无列则 B15/B16 无落点，属必要延伸，已加并在索引注记中按既有纪律暂缓索引。
5. M1/M7/M9/m9 的同源连带（§0、Q1 顺延余数 24、T-M4 的 13、T-M1g 的 :160-198、SKIN §0 的 RVM 措辞）：评审只点了部分位置，同源数字/措辞一并改了，否则文件自相矛盾。§8/§5 修订记录中注明。
