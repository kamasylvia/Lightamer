# M5-3-03 SUMMARY — 全景 UI 与收口批（wave 3）

> 执行批 2026-10-16（夜间全自动授权「开跑，不要停」在案）。规格 =
> M5-3-03-PLAN.md（派发注记 checker 5 minor 同批采纳，落点分账 =
> DECISIONS §1）；偏差/定夺正本 = M5-3-03-DECISIONS.md（§1-§6）；
> G5 机检正本 = phase 根 `g5-redline-checks.txt`；G4 evidence 正本 =
> `evidence/opencv-structural-compare/report.md`（政策 B 磁盘路径）。

## 任务序与提交

| 任务 | 产物 | commit |
|---|---|---|
| T1 | 菜单第三项 `browser_menu_pano` + 简形 sheet（零控件四件）+ `onPano` seam + `panoMergeHandler` seam + **ContentView 穿线第四段**（minor-1）+ LightamerApp enqueue（`.pano` + deGhost false 显式形 + tag nil）+ `toast_pano_queued` + xcstrings 8 键尾块纯插入 + plan front-matter 补登记 | `fe3fc5f` |
| T2 | `PanoFailureCopy` typed 三态 zh 映射（failureKey 纯函数 + failureMessage 消费面，显式 switch 静态键）+ failureHook 消费点接线 + `PanoMergeUITests` 5 法 + Project.swift App 数组登记 + BUNDLE-MAP APP 增行 + tuist generate 恒末位（L041） | `2d57bc37` |
| T3 | G4 OpenCV 结构对照 evidence（仓外 uv + opencv-python-headless 5.0.0）：probe 脚本 + 原始输出 + report.md → `evidence/opencv-structural-compare/`（政策 B 磁盘路径，**零主仓 commit**，DECISIONS §2/§4） | 磁盘产物 |
| T4 | G5 十一项机检 transcript → phase 根 `g5-redline-checks.txt` + G6 MANIFEST → `.work/gui-acceptance/m5-3/MANIFEST.md`（磁盘产物，M5-2 同形） | `6699da3e` |
| T5 | 收口轮（App 定向 + 批准全套 `--all`）+ 零 diff 自证终验 + 本批文档（本提交） | 本提交 |

## UI 证据（KD-1/KD-2/KD-3 交付面）

- **菜单第三项**：legacy face merge 组三项并存（HDR 合并 / HDR 合并
  （Mertens 快速）/ 全景合成）——`onPano` nil = 隐藏，既有 gate 形；
  前两项与 focus/stack 项 0 deletions（T1 diff 纯 additive 亲证）。
- **简形 sheet**：标题/正文/取消/开始四件，零档位控件（OQ-7）；正文单键
  承载四生效值（同视点 / 重叠 ≥30% / 2 亿像素帽超限等比缩小 / 恒自动
  裁边）。SwiftUI `.sheet`——L057 runModal 族不适用（构造性豁免）。
- **enqueue 接线**：`kind: .pano` + `MergeParams(deGhost: false, tag: nil)`
  （deGhost pano 腿不消费，App 恒传显式 false；tag nil →
  `defaultTag(.pano)` = "pano" → `_pano` 分账名）+ `toast_pano_queued`。
- **typed 三态 zh 映射面**：failureHook 消费端显示层映射——
  `panorama alignment failed` → `pano_error_alignment`（全景对齐失败）/
  `panorama images disconnected` → `pano_error_disconnected`（全景照片
  不连通（重叠不足））/ `panorama canvas invalid` → `pano_error_canvas`
  （全景画布无效）；typed detail 保留、AppError 样板头剥除、非前缀
  逐字节透传（既有错误面零变化）。Core 错误词汇零改（G5 全域零 diff）。

## zh 键族（KD-4；8 键尾块纯插入 136/0）

`browser_menu_pano` / `pano_dialog_title` / `pano_dialog_body` /
`pano_dialog_start` / `toast_pano_queued` / `pano_error_alignment` /
`pano_error_disconnected` / `pano_error_canvas`——历史键字节与顺序零触碰。
`zh-audit --check` **PASS（1651 source / 1890 catalog / zh complete）**；
三 error 键在 T1 边界的 3 ORPHAN 由 T2 消费点闭合（MISSING 全程 0）。
提取器硬化对账（V15）实跑两轮在案。

## G4 结构对照结论（KD-5；非门值）

七段链段序一一对应（特征→匹配/边门→估计→射线 BA→波校正→球面投影→
增益→融合→裁切）；匹配/BA/波/画布帽门值族同源同值（Lowe 0.3 /
conf>.6 ∧ inliers≥10 / HORIZ / 200MP）；增益与融合/裁切两处结构分叉 =
OQ 裁决在案的有意 Lumen 形采纳（OpenCV GainCompensator 逐通道 vs scalar
min-norm；multiband+GraphCut vs 512 tile 几何羽化带 + 恒 inner_crop
直方图栈）——**零意外缺口**。运行环境 = opencv-python-headless **5.0.0**
（Stitcher 组件 getter 已被绑定移除；Lumen 腿锚定六 API 全数活体可用并
链级实跑：conf 2.9624 / inliers 213 / BA focals 2553.605/2553.503——
比组件内省更强的结构证据）。仓源码树零 opencv 代码（26 grep 命中全为
头注归属注记）。正本 = report.md（非门值声明卷首）。

## G5 红线机检（KD-6；transcript 正本 `g5-redline-checks.txt`）

十一项全绿：红线路径（LightamerIOP/ + LightamerCore/ + `*.metal`）全域
零 diff（base 60aad61）→ 腿体/`writeFloatTIFF`/ProvenanceReplay 字节零
→ dependencies 块零 diff（Project.swift = 测试登记单行）→ 禁系统随机源
grep **含 `\.random\(` 底层形态**（minor-4 硬化门）零命中 → runModal 门
零 → `String.LocalizationValue` 插值前缀禁形代码零（唯一命中 =
:1921 禁形文档注释）→ sidecar schemaVersion 零触 → xcstrings 纯插入
（删除行 0）→ SessionBrowserView 0 deletions → zh-audit PASS →
App 定向轮 757/4/0。**六 kind 零回归三面合一**：P1 快照负测
（PanoMergeKindTests）+ P2 `rowProvider` nil 零漂移负测（PanoLegTests +
02 批 IOP 682/1/0）+ 本批 UI 前两项零 diff——全套 `--all` 终验为第四面。

## G6 走查 MANIFEST（KD-7；Manual-Only）

`.work/gui-acceptance/m5-3/MANIFEST.md` 五行配方：①三重叠样张合一张
（菜单三项并存 + sheet + 产物落格）②crop 观感（无效边缘裁净）③`_pano`
分账落盘名 + provenance details ④typed 失败 toast（无重叠样张 →
disconnected zh 文案、canonical 短语不漏出）⑤产物重导入编辑链
（M4-1 sRGB 域 readout）。fixture 来源注记 = 同视点扫幅样张（RAW
bracket 不适用；无实拍时合成 TIFF 序列替代，Lumen diagnostics 先例）。
Manual-Only 依据引用在卷首；执行 = 用户/orchestrator 安排，证据回填
ACCEPTANCE——VALIDATION 挂「走查证据待回填」（M3-4 先例）。

## 收口轮数字（2026-10-16）

| 轮 | 结果 | 备注 |
|---|---|---|
| App 定向轮（T2 后） | **757/4/0**（372s，peakRSS 2832MB） | 752 + 5（PanoMergeUITests），零 MEMFAIL 零 crash |
| 全套 `--all`（批准轮，exit 0） | **TOTAL 3631/24/0**（2102s） | IOP **684**/1/0（453s/7731MB）/ IOPParity **456**/3/0（775s/7803MB）/ Layers **466**/4/0（163s/1169MB）/ Library **636**/4/0（78s/617MB）/ Sessions **279**/4/0（69s/1626MB）/ Export **353**/4/0（198s/6455MB）/ App **757**/4/0（366s/2832MB）——全部 8G 门内零 MEMFAIL 零 crash；原始日志 = phase 根 `all-run-m53-03.log` |

## 基线对账链（以各站实测 bundle 和为锚；§VALIDATION 全表引用）

**3539/22/0**（M5-2 修复后基线，`--all` 3538 + E-1 回归法）
→ +43（M5-3-01：Feature 9 / Match 9 / Camera 7 / MergeKind 8 / Golden 5 /
Provenance 5）= **3582**（01 后拼表）
→ +44（M5-3-02 实测净增：Warp 8 / Gain 14 / Crop 10 / Leg 11 / Probe 2
− stub 退役 1，**含验收波两枚回归法**〔第 11 腿 straggler + E-omp-1
非对称几何回归〕）= **3626**（enter-03 实测基线，IOP 684 亲证——02
SUMMARY 记账口径 3623 与此差 3 = 上述验收波增量，GOAL-STATE 02 行
bundle 数字为证）
→ +5（本批 PanoMergeUI 5）= **3631/24/0**（本批 `--all` TOTAL 逐位闭合）。
估数 +5..8 下沿命中（5 法）；skip 24 身份 = 21 M5-1 在册 + 1 Mertens
探针 + 2 Pano 探针（env 门），零静默跳过。

## 偏差与发现（DECISIONS §1-§6 详）

1. checker 注记五项采纳落点分账（①本批 / ②④⑤前批已落 / ③转写残迹）。
2. T3/T4 evidence 与 MANIFEST = 政策 B gitignore 路径磁盘产物；T4 tracked
   交付 = G5 transcript（phase 根，perf.md 同位）。
3. OpenCV 5.0 绑定面收缩（组件 getter 移除）→ 结构探针改 Lumen 腿段
   活体实跑形；`apply2` 返回 = 2×2 展平 tuple（记录供后用）。
4. typed 映射面双层拆分（纯函数 + 消费面显式 switch 静态键，V14 纪律）。
5. 测试桩腿 bump 契约 = 2N+5（3N+6 恒式分解）。

## 验收与续接

- **双重验收待派**（`dual_acceptance = true`，m1）：待 orchestrator 派
  zcode 独立验收 → PASS 后**串行** omp 二验（严禁并发；可选 omp 实机 G6
  取证回填），结论落 `M5-3-03-ACCEPTANCE.md`（本批未创建——验收波产物）。
- **C 档第 3 门（Phase 签核前停）**：`M5-3-VALIDATION.md` 成文 drafted 态，
  签核待用户过目 verify-work 结论。
- **M5-3 phase 小结**：三 plan 合计 **+92 实测净增**（01 +43 / 02 +44 实测
  含验收波回归法 / 03 +5），基线 3539/22/0 → **3631/24/0**（`--all`
  TOTAL 亲证）；IOP-PANO-01 全 SC Delivered（VALIDATION SC 三列对表）。
- **M5-4 收口交接**：①M5 VALIDATION 汇总（M5-1/02/03 三 phase VALIDATION
  就绪，本 phase 载荷 = SC 终验翻账 + 挂账汇编）②「全史瘦身手术第二次」
  触发（SPEC 正本 = `.work/gsd/research/HISTORY-SLIM-SURGERY-SPEC.md`；
  strip 集按 SPEC 重算**非空才动手**，零命中停手上报；filter-repo 后重
  add remotes〔L070 坑〕；push 收敛主会话）③双重验收余项（本批 + phase
  签核）先于 M5-4 汇总闭合。
