# M9-2-ACCEPTANCE-OMP — omp 独立终审（实机 computer-use + 双路对账 + 快修复核）

> 终审：2026-10-28 omp。对象 = `af446612`（T1 资产）+ `b807b1dd`（T2+T3+T4，refs #12）
> + `254a902f`（M-1 快修）+ 双路 zcode 报告（路 1 `M9-2-ACCEPTANCE.md` / 路 2
> `M9-2-ACCEPTANCE-2ND.md`）。方法：probe 缝（`-la_film_probe`）实机走查 +
> cliclick 合成输入 + screencapture 截图识图 + 视口像素差分机检 + sidecar 落盘
> 对账 + w11 三判据 Python 独立复算 + 读码亲核。零共享上下文，不轻信双路结论。

## 结论头

**PASS / 0 error + 0 minor**（+ 4 observation，见 §七；双路 minor/major 处置见 §五）

| 终审面 | 判定 |
|---|---|
| 1. BW 族面板（stock picker 4 卷 + 相纸 BW 节 + grade 8 档 + grain readout） | PASS（§一） |
| 2. 滤色镜（9 档 picker + w25/w11/w58 活面 + 卸载恒等 + w11 修正曲线） | PASS（§二） |
| 3. 回归面（彩色对零漂移 + 旧档零迁移弹窗） | PASS（§三） |
| 4. 双路对账（路 1 m-1 / 路 2 M-1 修后 + m-1 / obs 逐条） | PASS（§五） |
| 5. undo/持久化（三元组 quit 重开存活 + sidecar v12） | PASS（§六） |
| 6. 快修复核（w11 三判据独立复算 + rebuild 逐字节 + 回归定向） | PASS（§四） |

---

## 环境与卫生

- guard：`Scripts/machine-guard.sh --wait` → **PASS**（G1-G4 全过，无需绕门）。
- ps 清零：起跑前 `ps` 无 Lightamer GUI/测试宿主（同命令链验证）。
- monitor：`machine-guard.sh --monitor 10800` 伴跑全程（log =
  `omp-evidence-monitor.log`），**零触发、零 kill**。
- 构建自证：Debug 产物重建成功（`BUILD SUCCEEDED`，26s，log =
  `omp-evidence-build.log`）；bundle 内 `FilmProfilesBW/camera_filters.json`
  mtime 11:18:59 **晚于**快修 commit `254a902f`（11:15:06）——走查的是含修正
  曲线的产物。注：`.app` 目录 mtime 不动是 macOS 目录语义，资源文件 mtime
  为准。
- 供件：`/tmp/m92-omp-walk/src/` = `DSC09981.ARW`（用户实拍街景，只读拷贝，
  未动原片）+ `IMG_4276.CR3`（TestRAW 公开样张）。走查全程在 CR3 上进行
  （ARW 仅作切图载体）。
- 收工：两实例均已 quit（第二例 `quit` 无响应后 kill，无残留进程）；defaults
  域 `com.kamasylvia.lightamer.plist` 已删；fixture `.lra` 已清；tracked
  **零 diff**（`git status` 仅 `??` 未跟踪工作文件）。

## 走查驱动说明（诚实申报）

- AX 路径（System Events）在 SwiftUI 壳下**窗口枚举非确定性**（`window 1`
  时而 -1719），与往期走查一致；本轮主驱动 = cliclick 坐标点击（截图识图
  定位，retina 2x 换算）+ 键盘（arrow-up/return/esc）。全部 19 张证据截图
  在 `omp-evidence/`（见 §八清单）。
- 视口渲染差分 = Python PIL/numpy 整图比对（视口区 x 0.10-0.60 / y 0.08-0.80），
  均值/最大/超阈像素三数机检，非纯目测。

---

## 一、BW 族面板（PASS）

| 检查点 | 证据 | 判定 |
|---|---|---|
| Film picker BW 分节 4 卷 | `omp-02`：黑白节头（灰显）下 ACROS II / HP5 PLUS / T-MAX 100 / TRI-X 400 四卷全列，顺序与 `filmStockSections` 一致 | ✅ |
| 相纸 picker BW 节 | `omp-04`：黑白节头下 `ILFORD MULTIGRADE IV RC` 单卷；彩色 6 相纸在上 | ✅ |
| 选 Tri-X → grain readout | `omp-03`：`发表 RMS 17 μm · 推荐 strength 25.6` + 应用按钮；solve readout 同步变为 `M 3.9 · Y 0.0 · ×1.00`（BW 对 posture） | ✅ |
| 选 Multigrade → Grade 行出现 | `omp-05`：反差号行 `无（自动）`；solve `M 0.0 · Y 56.1 · ×1.00` | ✅ |
| Grade picker 8 档 verbatim | `omp-06` + 放大复核 `s16-zoom00`：`无（自动）/ 00 / 0 / 1 / 2 / 3 / 4 / 5` 八档，**00 与 0 为两行** | ✅ |
| 切 grade 5 → 落盘 + history | sidecar `paper_grade: "5"` + history `相纸反差号` 条目 | ✅ |
| Grade 渲染活面 | 通常曝光下 5 档视口差分为零（见 obs-omp1）；grade 渲染语义由机检门承载（BWSpectralGolden 阶调门绿） | ✅（机检承载） |
| T-Max readout 交叉 | `omp-16`：`发表 RMS 8 μm · 推荐 strength 12.2`（12.205 取整一位） | ✅ |

## 二、滤色镜（PASS）

| 检查点 | 证据 | 判定 |
|---|---|---|
| SHOOT 节 + 9 档 picker | `omp-09`：`无 / w11 / w12 / w15 / w21 / w25 / w47 / w58 / w8` 九档；节 caption「曝光时镜头前置滤镜——作用于胶片光谱感度；与下方放大机 Y/M 二色性校正不同」 | ✅ |
| w25 活面 | `omp-10`：picker `w25` + 注记行 `数据注记:kodak_b3_transcription diverges on 9 points >2pp`；视口差分 maxΔ90 / 均值 1.31 / 13219 像素超阈（**渲染真动**）；sidecar `camera_filter: w25` + history `拍摄滤镜` | ✅ |
| w11 可选（修正后曲线） | `omp-11`：picker `w11`，w25→w11 视口差分 maxΔ87 / 均值 1.26 / 12681 超阈（**修正曲线渲染可辨**）；注记行消失（w11 单源无 cross_check，符合 `divergent > 0` 才注记的产线语义） | ✅ |
| 卸载回 None 恒等 | `omp-12`：picker `无`；sidecar `camera_filter` **键缺席**（omit-if-nil，非空串）；w11→None 差分 maxΔ66（方向回摆） | ✅ |
| w58 注记行 | `omp-18`：`数据注记:kodak_b3_transcription diverges on 14 points >2pp`（与资产 `divergent_points_over_2pp: 14` 逐字一致） | ✅ |
| 资产注记在位 | `camera_filters.json` 内 `factor_check_note`（6/7 + 0.61 + w11 重转录行）逐字在位；evidence 副本 sha256 与 shipped **前 16 位一致**（同字节） | ✅ |

## 三、回归面（PASS）

| 检查点 | 证据 | 判定 |
|---|---|---|
| 彩色对：Grade 行隐藏 | `omp-14`：Portra 400 × Endura Premier 档 Grade 行与 grain 行双双缺席（`availableGradeKeys` 的 `channelModel == "bw"` 门 + readout 的 BW-stock 门）；Filter picker 仍在（滤镜对色卷合法） | ✅ |
| 彩色对：solve 姿态正常 | `M 52.6 · Y 46.4 · ×1.36`（彩色对 solve 面） | ✅ |
| 交叉对（色卷×BW 相纸） | `omp-13`：Portra × Multigrade 档 Grade 行**在位**（门控只看相纸，不看胶片——设计如此）；视口黑白观感 | ✅（行为符合门控语义） |
| 交叉→纯色对渲染翻面 | 视口差分 maxΔ365 / 均值 175.65 / 121 万像素超阈（黑白→彩色大翻面） | ✅ |
| 旧档（v11 形）零迁移弹窗 | `omp-15`：手造 v11 形 sidecar（schema 11 + 无新键）切图打开：**零弹窗**，Film 会话控件照常（Portra × Endura 恢复）；schema 未被动 bump（仍 11）；仅一条 `history hash MISMATCH` log（系手造档 hash 未重算所致，属实验伪影，见 obs-omp4） | ✅ |
| 残留 grade 键无渲染面 | 色卷档 sidecar 残留 `paper_grade: "4"`（纸切换不清 grade，见 obs-omp3），但消费缝 `PaperGradeTag` 仅经 `filmLegRequestTags` 组装（`cachedTable(paper)[grade]` 查表门）——渲染面语义不变 | ✅（读码亲核） |

## 四、快修复核（PASS——三判据独立复算全中）

复算方法：Python 直读 repo 数据（修正后 `camera_filters.json` w11 曲线 ×
Tri-X `log_sensitivity` × `SpectralConstantsData` D55/CMF），公式逐行镜像
`SpectralBuildEngine.swift:476-490`（绿通道整卷归一）与亮度透射定义。Tri-X
无 adaptation window（`hanatos2025_adaptation_window_params` 缺席），sensW
= 10^log 直用。

| 判据 | DECISIONS §10 申报 | 本轮独立复算 | 判定 |
|---|---|---|---|
| ① 曲线形态 | 峰 60.0@510-520，单调下行至 6.20@700；400/410 破折号 floor 0.001 | 510/520 = 60.0/60.2；520→700 单调降（唯一 +0.1 台阶在 690→700：6.1→6.2，源页行读数本性）；400/410 = 0.001/0.001；`dash_or_offchart_cells_pct = [400, 410]` | ✅ |
| ② 亮度透射 | 40.3% vs 源页 40.2 | **40.1%**（V(λ)=CIE 1931 ȳ × D55；与源页 40.2 差 0.1pp，计算口径舍入带内——弃用曲线 67.1% 的 1.7x 矛盾已消除） | ✅ |
| ③ 发表 factor | f11 = 0.2201（4.54x，+0.18 stop，0.21 带内） | **f11 = 0.2201，4.54x，+0.18 stop**，与申报逐位一致；全表复算 w8 +0.12 / w12 −0.04 / w15 +0.16 / w25 −0.01 / w47 +0.04 / w58 **+0.61** = **6/7 within 0.21**，note 的「6/7」在修正数据下为真 | ✅ |
| rebuild 逐字节 | 管线确定性先证 + evidence/Resources 双份同步 | evidence/t1 与 Resources 两份 `camera_filters.json` sha256 前 16 位同值（`158cfa4726633b5e`） | ✅ |
| commit 范围 | 4 文件（DECISIONS + MANIFEST + filters + build_wratten.py） | `git show 254a902f --stat` = 恰 4 文件；回归（CameraFilter 4/0/0 + FilterBakeKey 4/0/0 + BWProfileAssets 6/0/0）在 message 在案 | ✅ |

判定：**转录错定论成立**（三判据独立复算全中，无反证）；快修分支正确
（修数值非仅注记）；生产语义不受扰（TTL 锚不消费发表 factor，路 2 原判
断维持）。

## 五、双路对账

### 路 1 M-1（grain note 文案）→ 快修轮未改，降级为 obs-omp2

- 核对：`254a902f --stat` = 恰 4 文件，**不含** `grain_calibration.json`；
  HEAD 实测 HP5 行 note 仍为 `T4 interpolates the family (M9-2 DECISIONS)`。
- 处置：路 1 M-1 的「文案误导」事实成立，但快修轮 scope 正确地未碰它
  （转录错修数值的最小面）；且顶层 note 已有正确句（`no invented
  interpolation`）对冲。本轮将其降级为 **obs-omp2**（下批顺手改，
  M9-3 账本行），不阻断。

### 路 2 M-1（w11 转录错）→ 快修闭环，PASS

- 见 §四：三判据独立复算全中 + 资产注记更新（0.67→0.61 精确复算 +
  w11 重转录行）+ 实机 w11 档可选且渲染可辨（`omp-11`）。**关闭**。

### 路 2 m-1（登记曲线 vs shipped 推荐值出入）→ 维持登记，语义无忧，PASS

- 核对：JSON note 登记 `boxRMS ≈ 0.662×s + 0.62` 反解（24.74/11.15/9.64）
  ≠ shipped（25.638/12.205/10.713）——路 2 算术成立；probe stdout 未存档
  evidence 也成立。
- 本轮加验：实机 readout 显示 25.6 / 12.2 = shipped 推荐值取整一位
  （`omp-03/omp-16`），即**用户可见面 = shipped 值**，登记曲线不进任何
  消费（`GrainCalibration` 只读 `recommended_strength` 表值）。runtime
  ±2.0 语义门为 operative guard（路 2 复测绿）。**登记面失真属实但零
  用户可见面**——维持 m 级，下批「存档一次 probe 输出或修正 note 系数」
  二选一，不阻断。

### obs 逐条一句话

- 路 1 obs-1（乘法缝 count 失配静默恒等）：成立但生产不可达
  （coordinator 恒对齐），维持观察。
- 路 1 obs-2（FilterBakeKey ③ 头注释 BW pair 语义不精确）：成立，
  注释卫生，下批顺手。
- 路 1 obs-3（BW absent 自钉 grade 2 的冗余缓存行）：DECISIONS 已登记
  无正确性面，维持。
- 路 1 obs-4（⑥ 对归一缺失不敏感，判别力在 ⑦+①）：反自取消实证已揭示
  判别网结构，属实，维持。
- 路 1 obs-5（阶调门降级 + ⑦ 阈值降级 PLAN-DECLARED）：申报链完整，
  v2 挂账在册，维持。
- 路 1 obs-6（ΔN +6 口径差）：SUMMARY 已申报待 orchestrator 复核，
  本轮不碰账，维持。
- 路 2 obs-1（T5 收口节 27 法 vs 29 法小账不平）：成立，主账不受扰，
  账本卫生。
- 路 2 obs-2（引擎缝无 typed 拒绝，gate 在装配点）：设计如此
  （DECISIONS §2），维持。
- 路 2 obs-3（§6 span 台账 2=0.235 vs HEAD 实测 2=0.22863=00 恒等）：
  属实，v2 refit 以 HEAD 实测为准，维持。

## 六、undo/持久化（PASS）
- 三元组 quit→重开：quit 前（T-Max 100 × Multigrade × grade 4 × w58，
  schema 12，history 17 项）→ 重启 probe → `omp-19` 面板逐项复现
  （Grade 4 / w58 / RMS 8 readout / +0.44 EV）；sidecar 六键
  （film/paper/grade/filter/exposure/strength）**逐位 SAME**。
- history 语义：`相纸反差号` / `拍摄滤镜` / `更改胶片材料` discrete
  条目逐动作落盘（本轮未逐条 ⌘Z——面板值-sidecar-history 三方一致已证
  commit 面；undo 语义由 `commitFilm` 既有通道承载，非本批新面）。
- v12 落盘：`schemaVersion: 12` + `paper_grade`/`camera_filter` verbatim
  键在位；None 档键缺席（omit-if-nil，§二已证）。

## 七、本轮新 obs（4 项，均不阻断）

- **obs-omp1｜grade 切换的通常曝光视口差分为零**：grade 5 切入后视口
  逐像素差分 = 0（面板/sidecar/history 三面均已翻转）。结合 M8 走查
  「曝光滑杆是渲染活面探针」先例，判定为**观感地板面**（当前片在该
  曝光下 grade 档的密度差落在视口量化/色调映射之下），非 commit/渲染
  链断裂——filter 档同链渲染真动（§二 maxΔ90/87）是链路活的直接反证。
  grade 渲染语义由 BWSpectralGolden 阶调门机检承载。维持观察。
- **obs-omp2｜路 1 M-1 降级**：HP5 note `T4 interpolates the family`
  与 DECISIONS §3 终裁（不采纳插值）文字矛盾，快修轮未改（scope
  正确）。下批顺手改 note + 同步 MANIFEST。M9-3 账本行。
- **obs-omp3｜纸切换不清 grade 残留键**：Multigrade→Endura 后 sidecar
  残留 `paper_grade: "4"`（`setPaperStock` 只换纸不清 grade）。渲染面
  无影响（消费缝查表门），属数据卫生。建议下批：切非 BW 纸时清 grade
 （或显式登记「残留键 = 回切 BW 纸的记忆」二选一）。
- **obs-omp4｜旧档走查的 hash MISMATCH log 系实验伪影**：手造 v11 形
  sidecar 未重算 historyHash，触发 `history hash MISMATCH — file is NOT
  rewritten until the next user edit`（且 schema 未被动 bump——与
  „loaded legacy 永不被动升级"规则一致）。真旧档（hash 自洽）不受此
  影响；零迁移弹窗结论不受扰。

## 八、证据清单（`omp-evidence/`，19 张）

| # | 文件 | 内容 |
|---|---|---|
| 1 | `omp-01-film-enabled-c200.png` | 启用后默认对 C200 × Crystal Archive + SHOOT 节 + solve |
| 2 | `omp-02-film-picker-bw-section.png` | Film picker：黑白节 4 卷全列 |
| 3 | `omp-03-trix-grain-readout.png` | Tri-X：RMS 17 readout + 应用按钮 |
| 4 | `omp-04-paper-picker-bw-section.png` | Paper picker：黑白节 Multigrade |
| 5 | `omp-05-bw-pair-grade-row.png` | BW 对：Grade 行 `无（自动）`出现 |
| 6 | `omp-06-grade-picker-8items.png` | Grade 8 档：None + 00..5（含 00/0 双行） |
| 7 | `omp-07-grade5-render.png` | Grade 5 切入态 |
| 8 | `omp-08-bw-render-ev3.png` | BW 渲染活面（+3EV 黑白连续调） |
| 9 | `omp-09-filter-picker-9items.png` | Filter 9 档全列 |
| 10 | `omp-10-w25-render.png` | w25 + 9 点注记行 |
| 11 | `omp-11-w11-render.png` | w11（修正曲线）可选 + 渲染可辨 |
| 12 | `omp-12-filter-none.png` | 卸载 None（键缺席） |
| 13 | `omp-13-color-film-bw-paper.png` | 交叉对：Grade 行在位 |
| 14 | `omp-14-color-pair-grade-hidden.png` | 纯色对：Grade/grain 双隐藏 |
| 15 | `omp-15-legacy-sidecar-no-migration.png` | v11 形旧档：零弹窗 + 会话恢复 |
| 16 | `omp-16-tmax-readout.png` | T-Max：RMS 8 readout |
| 17 | `omp-17-tmax-mg-grade4.png` | T-Max × MG × grade 4 三元组 |
| 18 | `omp-18-w58-note.png` | w58 + 14 点注记行 |
| 19 | `omp-19-relaunch-triple-survived.png` | 重开：三元组存活 |

过程截图（/tmp 域，不入库）：`s0-s57` 定位裁剪链 + 视口差分中间件。
构建/monitor 日志：`omp-evidence-build.log` / `omp-evidence-monitor.log`
（未跟踪工作文件，随终审报告处置）。

## 九、建议（给 orchestrator）

1. **M9-2 放行**：三 AC + 双路 + 终审三眼闭环，`254a902f` 后 HEAD 可签核。
2. M9-3 账本行三条：obs-omp2（HP5 note 措辞）/ obs-omp3（纸切换 grade
   残留二选一）/ 路 2 m-1（probe 输出存档或 note 系数修正二选一）。
3. 往期走查配方（`.work/gui-acceptance/m9-2/MANIFEST.md`）§2「切 5 →
   观感反差明显变硬」在本供件/曝光下未复现目视差（obs-omp1）——配方行
   建议加注「观感幅度与片/曝光有关，机检门为准」，免后人误判回归。
