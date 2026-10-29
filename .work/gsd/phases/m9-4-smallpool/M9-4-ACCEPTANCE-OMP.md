# M9-4「小件池」omp 终审 — 实机（computer-use）+ B-1 修复验证 + 双路对账

> 审期：2026-10-29 23:27 → 2026-10-30 00:12。对象 = 九 commits
> `358523ce..83006dcb`（refs #14）+ 修复轮四 commits `861af688` / `b649de7f` /
> `ac7b633a` / `46a01e07`。工作树 HEAD = `46a01e07`，**tracked 零 diff**
> （收工亲核 `git status --porcelain | grep -v '^??'` = 0）。
> 正本输入 = SUMMARY / DECISIONS §1..§13 / 双路报告 / gui-acceptance MANIFEST。

## 结论头

**PASS / 0 blocking · 1 major（M-1′，Show in Finder 路径解析）· 0 minor · 3 obs**

- 主件（M9SM-01 ColorWheels v3 + process v3 bump + 迁移 UX）实机通过，B-1
  修复**三重独立证据成立**（源码 target / 独立 Float64 探针 / 实机像素等值）。
- 尾件四件中三件实机通过（Filmstrip stars / XPan 三档 / LUT 编码表 10 行）；
  **Show in Finder 三门「门在、UI 在、AX id 在」，但 `row.imagePath` 未解析
  → kind 0/1 静默 no-op，仅 kind 2（绝对路径）真定位**（M-1′，机制已独立复现）。
- 双路遗留：路 1 三 minor → 两关一留（措辞类）；路 2 M-1 已由修复轮闭环、
  m-1 随 B-1 重测消解、obs×4 全部「记录备查」成立。

---

## 一、环境与基线自证

| 项 | 事实 |
|---|---|
| 构建 | `xcodebuild build -workspace Lightamer.xcworkspace -scheme Lightamer -configuration Debug -destination 'platform=macOS'`（`-disableAutomaticPackageResolution`，**零代理**）→ **BUILD SUCCEEDED**；`Lightamer.app/Contents/MacOS/Lightamer` mtime **23:36:59** > `46a01e07` 提交时刻 23:27:55 ✓（容器 `Lightamer-glcj…`；SPM 依赖本轮被整体重编，因缓存面在上批被清） |
| machine-guard | 首判 **BLOCK G4**（Data 20986MB<25GB）→ 清可再生面（两个陈旧 DerivedData 容器 2.35G）后 23804MB **仍 BLOCK** → 按三批 §9 先例**透明越门**，`--monitor 10800 &` 自 23:38:06 伴跑，ceiling 9GB，**零 RSS-KILL**（日志仅 start 行） |
| 单重活 | 全程唯一 GUI 实例（probe 直启），起跑与收工 `pgrep` 亲核；无并发 xcodebuild/test 宿主 |
| 收工 | App quit；monitor 已停；TMPDIR 侧 fixture 目录已删；defaults 零写入；tracked 零 diff |

## 二、逐面表（任务书 6 项职责）

| # | 职责面 | 结论 | 证据 |
|---|---|---|---|
| 1 | ColorWheels v3 迁移（B-1 正主） | **PASS** | 见 §三（源码 + 探针 + 实机像素 + 文案 + marker） |
| 2 | 迁移 UX 泛化四面 | **PASS**（gate 双入口之 film 侧 = 源码亲核 + M8-3 既有走查先例；cw 侧实机闭环） | `EditorState+FilmMigration.evaluate`（`hasFilmRecord \|\| hasColorWheelsEdits`）+ `ProcessMigrationInputs` 双挂点（FilmPanelView:49 / ColorWheelsPanelView:85）+ marker 二形实机落盘（`history` 尾部 `迁移至当前渲染代`，params 字节零改）+ copy 中性 5 键在屏 |
| 3a | Filmstrip stars | **PASS** | 标记菜单设 3 星（DB `images.rating=3`）→ 胶条行 AX `filmstrip.row.1 = "★★★"`（在屏 + 网格角标同步） |
| 3b | Show in Finder 三门 | **PASS（门）/ FAIL（解析）** | 三门 UI + AX id 在册，kind 2 档三路全真定位（Finder 窗口 2→3，`DSC00012.ARW` 选中「选择了 1 项」）；**kind 0/1 静默 no-op → M-1′** |
| 3c | XPan 三 ratio | **PASS** | 裁切比例菜单 10 项：`65:24（XPan）` / `2.75:1` / `6:17` 在册；选 65:24 → 值回显 + overlay 锁定 + 提示行「锁定 overlay 拖拽比例；该标记随附导出」 |
| 4 | LUT 尾件抽验 | **PASS** | `inspector.picker.lut.encoding.input` 菜单 33 项：场景组含 Sony S-Log3/S-Gamut3.Cine、Fujifilm F-Log2/F-Gamut、Canon Log2/Cinema Gamut、RED Log3G10/REDWideGamutRGB、BM Film Gen 5、DaVinci Intermediate、**DJI D-Log/D-Gamut**；显示组含 P3-D65 G2.6、P3-DCI G2.6、Rec.2020 BT.1886 |
| 5 | v1/v2 冻结臂回归 | **PASS**（源码级亲证；实机 v2 臂为迁移前态本身） | `grade_color_wheels` 函数体 baseline `7f089c9d` vs HEAD **逐字节相同，md5 = 8943b9a434132c48f62b66d490c7664a**；`grade_color_wheels_v3` 仅 HEAD 存在（baseline 缺席）；迁移前文档实机为 v2 三臂（`inspector.trackball.colorwheels.{lift,gamma,gain}`，强度域 readout 1.000），迁移后为 v3 四臂 |
| 6 | 双路对账 | **完成** | 见 §五 |

## 三、B-1 修复验证（gamma 倒数语义）— 三层独立证据

**① 源码层（HEAD 实读）**：`ColorWheelsLegacyConvert.fitLegacyGammaGain`
的拟合 target = `copysign(pow(abs(input), 1.0 / legacyGamma), c) * legacyGain`
（`ColorWheelsLegacyConvert.swift:137-141`），文件头 / fit doc / target 行三处
注记如实写「我方冻结 v1 渲染 = 1/γ 指数」。零疑问。

**② 数值层（omp 独立 Float64 探针，非产线 import，`/tmp/m94_omp_probe.py`）**：
按源码常量（B=17.52 / middleGrey=0.4135884 / ±6EV / Gauss-Newton 25 样本）
逐句镜像，同一份代码分别跑「pre-fix 直指数」与「committed 1/γ」：

| 场景 | pre-fix max（stops）/ 中灰 | committed max / 中灰 | DECISIONS §13 申报 |
|---|---|---|---|
| γ=1.2, gain=1.0 | **−2.3390** / 0.4792→0.3468（反转） | **−0.0253** / 0.4792→0.4788（保持） | 2.3390 → 0.0253 ✓ |
| γ=0.9, gain=1.0 | **+1.3521** / 0.3749→0.4515（反转） | **+0.0285** / 0.3749→0.3751（保持） | 1.3521 → 0.0285 ✓ |
| γ=1.1, gain=0.95 | **−1.1660** / 0.4257→0.3598（反转） | **−0.0196** / 0.4257→0.4255（保持） | 1.1660 → 0.0196 ✓ |
| common 锚（lift .02/γ .92/gain 1.06） | — | 0.0313（带 0.035） | 0.0313 ✓ |
| extreme 锚（lift 1.4st/γ .9/gain 1.08） | — | 0.1093（带 0.145） | 0.1317（同带内，构造点差异） |

→ 与修复轮申报**逐位同值**，且**复现了反转幅度**（证明该探针具备判别力：
若 target 回退，量级 1.2–2.3 stops，实机必肉眼可见）。

**③ 实机层（computer-use，迁移全流程真跑）**：构造 legacy 文档
（process=2 + 手写 colorWheels params：`gamma.color_offset=(1.2,1.2,1.2)`，
offset 键**缺席** = v1 语义）→ 打开 → 面板确为 v2 三臂 → 点
`film.migrate.button` → 确认 sheet（**文案已是中性新句式**：「旧色彩轮文档的
新轮会重新表达原观感（沿用原渲染行为；两端可能残留轻微近似偏差）」）→
Return 确认 → 落盘：
- sidecar `process: 2 → 3`；history 尾项 label = `迁移至当前渲染代`；
  colorWheels params 字节**原样**（gamma 1.2 保留、offset 仍缺席）= marker
  二形之 **cw verbatim** 形，与 §7 申报一致。
- 迁移前后同帧画布像素（窗口截图裁 canvas，254.6 万像素）：

| 指标 | 实测 |
|---|---|
| 平均编码亮度 | 0.7773 → 0.7770（Δ = **−0.0003，−0.04%**） |
| 线性化后 | **−0.0011 stops** |
| 逐像素 |abs diff 中位/90%/99% = **0.0000 / 0.0000 / 0.0000** |
| 偏移 >5% 编码值的像素 | 0.39%（边缘/文字抗锯齿） |

→ **方向保持、量级 ≈0.001 stops**；B-1 缺陷态本应 −2.3 stops（约 −70% 线性、
全画面可见），实机零翻转。**B-1 修复成立**。

**辅助**：迁移后 v3 面板为四轮（shadows/midtones/highlights/offset），
亮度 readout = **0.40 / 0.59 / 0.64 / 0.00 stops**、强度恒 1.00 —— 与「gamma
1.2 旧档 → lift/gamma/gain 拟合 + offset 零」的物理预期吻合（拟合把纯 gamma
变化分配到三影调段）。

**未做**：omp 未复跑测试套件（定向测试需 build-for-testing，G4 越门 + 单重活
纪律下留待入口批）；B-1 的机检承重由双路已跑的 `ColorWheelsLegacyConvertTests`
7/0/0 + `testGammaNonNeutralLegacyKeepsLookAndDirectionAtUpgrade` 负向探针
（15 红）承担，omp 以「源码 + 独立数值 + 实机像素」三角替代复核。

## 四、新发现 M-1′（major）：Show in Finder 三门对相对路径静默失效

**事实**（实机 + 独立复现，两处互证）：

1. 三门消费的 `row.imagePath` = `.lalb` 的 `images.image_path` **原始列**
   （`LibraryQueries:807`；`ImageLinker.resolve(...)` 未参与），
   `FinderReveal.revealIfPresent(path)` 直接
   `FileManager.fileExists(atPath: path)` + `URL(fileURLWithPath: path)`。
2. 三档路径实测（同一文档、同一会话、同一键盘驱动 `Down+Return`）：

| path_kind | DB 存值 | 门行为 |
|---|---|---|
| 2 绝对+UUID | `/private/tmp/.../DSC00012.ARW` | **真定位**：Finder 窗口 2→3，RAW 选中 |
| 1 卷相对+UUID | `private/tmp/.../DSC00012.ARW` | **静默 no-op**（窗口数不变） |
| 0 项目相对 | `Media/DSC00012.ARW`（文件确在项目 Media/ 内） | **静默 no-op** |

3. 机制独立复现（`/tmp/reveal2.swift`，纯 Foundation/AppKit）：
   非绝对串 `fileExists` 按 **进程 CWD** 解析、`URL(fileURLWithPath:)` 亦按 CWD
   拼成 `file://<cwd>/private/tmp/...` → 存在性判 false 或 URL 指向错误位置，
   `activateFileViewerSelecting` 无动作。同一绝对路径的对照调用**能**让 Finder
   定位（窗口 3、文件在窗内）——排除环境/权限因素。

**定性**：T4「Show in Finder 三门」的 UI/AX/门控/存在性 guard 全在位，缺的是
**路径解析**；默认导入（link 外部文件夹 = kind 1、项目内 Media = kind 0）都是
相对档 → 对用户即「点了没反应」。无数据风险、无崩溃。修复面极小（三挂点改用
`ImageLinker.resolve(imagePath:pathKind:...)` 的 URL，或 `FinderReveal` 收
URL 而非 String）；**建议作为独立 repair 单进下批**，不阻断本批 ColorWheels
主件收口。复现脚本与三档矩阵见证据目录。

> 说明：双路各自的 M-1 / m-acc3 只打到「断言力/申报」层面，未能穿透到行为层
> ——本条的鉴别需要真机三档路径对比，属走查面（MANIFEST §Finder 的执行）。

## 五、双路对账（逐条评一句 + 路由）

**路 1（PASS / 0B+0M+3m+3obs）**

| 项 | 评 | 路由 |
|---|---|---|
| m-acc1（`isEditingContinuous` 措辞） | **成立**：`ColorWheelsPanelView` 仅强度/亮度滑杆有 `onDragBegin→beginEditing`（:208/:229/:309/:324），四轮 trackball 只有 `onTick/onDragEnd`（:184/:291）——轮盘拖拽不进 D-H1 窗，迁移行 editingInFlight 守卫对其不触发（与 v1 对称，零回归） | 措辞修正挂 SUMMARY 勘误，代码零动作 |
| m-acc2（「前缀恒等」措辞） | **成立**：实现取 X5 分组尾插（scene 前 10 恒定、working 位 17、display 旧序 18..23），测试钉法正确；仅申报用词应收窄为「分组前缀」 | 文档勘误 |
| m-acc3（Finder 两法弱断言） | **已闭环**：`FinderReveal` 产线缝 + 常量单源 + 注入 seam 测试（`b649de7f`）确为真耦合；本条升级为 §四的行为级发现 | 由 M-1′ 接管 |
| obs-acc1/2/3 | 均「记录备查」成立（镜像域、探针留痕、锁内分配） | 无动作 |

**路 2（PASS with 1 blocking → 修复轮闭环）**

| 项 | 评 | 路由 |
|---|---|---|
| **B-1**（gamma 倒数） | **修复成立**（§三三层证据）；文案已如实改写（实机 sheet 在屏） | 关闭 |
| M-1（Finder 两法断言力） | **闭环**：产线缝 + 三挂点消费 + 常量钉拼写；行为层缺口转 §四 M-1′ | 关闭（M-1′ 另立） |
| m-1（残差带域） | **消解**：新 target 下 γ 偏离 0.2 实测 0.0253/0.0285，0.035 带在语义域成立（omp 探针复算同值） | 关闭 |
| obs-1（折键负测镜像域） | 成立：三负测为 `foldChain` 镜像域，缺真 PixelPipe 升号缓存 miss 集成负测；本批风险低（3 行折叠语句） | 挂后续集成负测 |
| obs-2（判别子设防单点） | 成立：`effectiveToneWheelParams` 掏空只被 gate 投影一法设防 | 记录；golden 可增 convert 腿显式断言 |
| obs-3（plan 外 6 文件） | 成立：T2 连带落位合理；`m9-3 omp-evidence/monitor.log` 混入 T5 commit 属卫生瑕疵 | 记录 |
| obs-4（G4 越门） | 成立：omp 本轮同样越门（20986→23804MB），monitor 零告警，追记如仪 | 本报告即追记 |

## 六、obs（omp 本轮新增，记录级）

- **O-1 编辑器 pristine 画布截断观感**：`.tif`/ARW 在编辑器主画布呈
  大面积极端假色（青/红/黄/白硬截断），而同图在 **cull 面**与**图库缩略图**
  正常。判为 `.sdrGamma` 直通（无 DRT/base curve）的**批次前既有观感面**
  （M2-6 pristine 语义），与 M9-4 改动无因果；B-1 的前后对比在**同一管线**内
  完成，不影响 §三 结论。路由：观感/DRT 尾件欠账（非本批）。
- **O-2 迁移行 AX 命名沿用 `film.migrate.*`**：泛化后仍用 film 前缀（代码注释
  已声明「历史拼写保留」）；建议下批改中性前缀或补注释到 key 族表。
- **O-3 走查 fixture 缺配方**：仓库无「v2 + 非中性 colorWheels」现成档，本轮
  以手写 sidecar（process=2 + params，FNV-1a 镜像算 paramsHash）构造。建议
  MANIFEST 增「legacy colorWheels 构造配方」一节，后续走查免考古。

## 七、机器纪律与卫生

- guard 越门（G4 23804MB<25GB）**透明申报**；`Scripts/machine-guard.sh
  --monitor 10800`（start 23:38:06，ceiling 9GB，零 RSS-KILL，收工停）。
- 唯一 GUI 实例；全部交互 AX（`AXPress` / CGEvent 键盘 `Down+Return`）驱动，
  坐标点击仅在 AX 不可达面（Sheet 确认键、右键菜单项）使用。
- 迁移 sheet 的确认键：AX 树不暴露 `film.migrate.confirm`（SwiftUI sheet 内
  按钮），以 `Return`（`keyboardShortcut(.defaultAction)`）触发——与 M8-3 走查
  记录同源，非缺陷。
- 收工：App quit、monitor 停、fixture 目录删、defaults 零写、tracked 零 diff。

## 八、证据清单（`.work/gsd/phases/m9-4-smallpool/omp-evidence/`）

| 文件 | 内容 |
|---|---|
| `build-omp.log` | `BUILD SUCCEEDED`（HEAD `46a01e07`，离线 SPM） |
| `monitor-omp.log` | guard monitor 起停（ceiling 9GB，零 kill） |
| `mig-before.png` / `mig-sheet.png` / `mig-after-return.png` | B-1 实机三段：v2 三臂 + 迁移行 → 中性文案确认 sheet → v3 四臂（迁移后） |
| `probe-22-cw-panel-visible.png` / `probe-21-cw-panel.png` | 迁移前 v2 臂面板（Lift/Gamma/Gain、强度域 1.000） |
| `mig-v3-panel-top.png` / `mig-v3-panel-bottom.png` | 迁移后 v3 四轮形态（高光 tooltip「推升或拉低高光（t = 1），单位档」） |
| `walk-09-editor-stars.png` | Filmstrip `★★★` 行 + 网格角标 |
| `walk-15-filmstrip-menu.png` | Filmstrip 右键菜单（「在 Finder 中显示」单项） |
| `walk-21-finder-reveal.png` | Finder 定位成功（`DSC00012.ARW` 选中、路径栏 private>tmp>…>img） |
| `walk-17-aspect-menu.png` / `walk-18-xpan-65-24.png` | 比例菜单 10 项 / 65:24 生效态 |
| `walk-20-lut-encodings.png` / `walk-19-lut-panel.png` | LUT 输入编码下拉（33 项，新 10 行在册）/ LUT 面板 |
| `probe-05-arw.png` | 首帧渲染（pristine 观感，O-1 对照） |
| 文本附录 | 下文 §附 |

## 附：关键 AX 读数（逐字，采自实机 AX 树）

- v3 迁移后四轮（`inspector.trackball.colorwheels.*`）：
  `shadows 亮度 0.40 / midtones 0.59 / highlights 0.64 / offset 0.00`，
  四轮 `强度 1.00`；`inspector.button.colorwheels.reset` 在册。
- 迁移前 v2 臂：`lift / gamma / gain` 三轮（无 offset），`强度 1.000`、`亮度 0.00`。
- 迁移 sheet：`film.migrate.sheet` = 「更新到当前处理代际？」+ 中性正文；
  `film.migrate.button` 迁移后消失（`alreadyCurrent`）。
- 裁切比例：`自由 / 原始图像 / 正方形 1:1 / 4:3 / 3:2 / 16:9 / 16:10 /
  65:24（XPan） / 2.75:1 / 6:17`（10 项）。
- 胶条：`filmstrip.row.1 = "DSC00012.ARW"` + `filmstrip.row.1 = "★★★"`。
- Finder 三门 AX id（源码常量单源）：`library.grid.action.finder` /
  `filmstrip.action.finder` / `menu.image.finder`。

## 验收界限

- 本报告 = 实机（GUI/AX/像素）面 + B-1 独立数值面；**测试套件不复跑**（双路已跑
  4426/4427，修复轮预批 +1 精确闭合）。
- film 侧迁移入口未做实机（无 film-record 档；M8-3 `walk-03` 先例 + 本次
  `ProcessMigrationInputs` 双挂点源码亲核）。
- LUT 只验「编码对可选 + 新行在册」，未做 .cube bake 导出（MANIFEST §7 的可选面）。
- 6:17 竖档未逐一拖拽验证（菜单在册 + 65:24 生效态已证，其余同臂代码）。
