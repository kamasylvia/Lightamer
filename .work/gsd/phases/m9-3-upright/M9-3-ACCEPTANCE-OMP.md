# M9-3-ACCEPTANCE-OMP — omp 独立终审（实机走查 + 修复验证 + 双路对账）

> 终审：2026-10-29 omp。对象 = 五 commits `d111ef2a`..`bee6b4bc`（refs #13）+
> 修复轮 `5a7d9225`..`4809f227`（十 commits）。输入 = `M9-3-SUMMARY.md` /
> `M9-3-DECISIONS.md` / 双路报告（`M9-3-ACCEPTANCE.md` 路 1 PASS+2m+6obs /
> `M9-3-ACCEPTANCE-2ND.md` 路 2 PASS+1E+3m）。方法：Debug 实机构建自证 →
> AX（自编 `axfind`/`axid`/`drag`/`rawsize`）驱动真实 app + cliclick 合成坐标 +
> screencapture 识图 + sidecar/裸库直读 + Python 独立复算（不走任何被测实现）。
> 全程单 GUI 占用；零源码改动。

## 结论头

**PASS / 0 error + 2 minor（新发现，非阻断）+ 6 obs**——E-1/M-1/M-2/M-3/m-1 五项
修复逐条实机闭环；E-1 以「旧角 19.875° 的联动重拟 == decoded 基准平面闭式」
数值门判死（对 display-域假设 7-16% 偏差，判别充分）。

| 终审面 | 判定 |
|---|---|
| 1. E-1 修复（旋转漏斗 frameSize = decoded 基准平面） | **PASS**（§一，闭式吻合 1e-8） |
| 2. M-1 修复（导线通道换锚 post-upright display 腿） | **PASS**（§二，crop+flip 激活态存域吻合） |
| 3. M-2 修复（第 5 条拒 toast） | **PASS**（§三） |
| 4. M-3 修复（拖拽路径选中态回写） | **PASS**（§三） |
| 5. m-1（minFraction 偏离披露） | **PASS**（头注在案） |
| 6. 基础回归（90°×2 / undo×2 / off 恒等 / 持久化） | **PASS**（§四） |
| 7. 双路对账（L1 m1/m2 + L2 obs-1） | 逐条评（§六） |

---

## 环境与卫生

- **构建自证**：`xcodebuild build`（workspace/scheme Lightamer，Debug，
  `-disableAutomaticPackageResolution` 离线）**BUILD SUCCEEDED**（147s，
  `omp-evidence/build.log`）；binary mtime **07:13:01 晚于** `4809f227`（07:04:42）。
  含 `0143d178` 键位勘误：bundle `en/zh.lproj/Localizable.strings` 内
  `upright_guides_cap_toast` 各命中 1。
- **机器纪律**：`machine-guard.sh --wait` PASS（heavy=0 / free 77% / Data 27.4GB）；
  同链 ps 清零核验（起跑前 0 GUI）；`--monitor 10800` 伴跑（`omp-evidence/monitor.log`），
  零 RSS-KILL；GUI 单实例串行走查。
- **收工**：GUI 已 quit（`pgrep` 零残留）；`defaults delete com.kamasylvia.lightamer`
  已清（探针临时项目曾污染 `library.recentProjects`，清后该域空）；tracked **零 diff**；
  证据全在 `omp-evidence/`（未跟踪工作产物，随本报告处置）。合成样张全在
  `/tmp/m93-omp-walk/`（不入库）。
- **供件**：用户实拍 `A_gate.ARW`（园博园牌楼，9504×6336，只读拷贝）+ 灰色 filler TIFF
  （探针二行需要不同 URL 触发二次装载）。未使用任何个人肖像/敏感目录。

## 一、E-1 修复验证（正主）— PASS

**判据构造**：`linkedSnapshots` 的 refit 是闭式；同一 crop/角度下，decoded 域与
display(AABB) 域的预言值相差 **7-16%**（远超声呐）。实测取一次**大旧角**联动：

1. 先行建立 committed `ashift.rotation = 19.875`（并 flip=5、crop 非全幅），
2. 按 `自动拉直`（同漏斗三入口之一，AX 可达）→ 新角 −0.45846948 + crop 重拟。

| 量 | 值 |
|---|---|
| 观测 crop（sidecar verbatim） | L 0.008500232 · T 0.011694611 · R 0.9914998 · B 0.9883054 |
| 独立复算 · **decoded 域**（w0=9504,h0=6336, old=19.875, new=−0.45846948） | 0.0085002 / 0.0116946 / 0.9914998 / 0.9883054 |
| 独立复算 · display 域（帧=AABB@old=11091×9189） | 0.0784 / 0.1618 / 0.9216 / 0.8382 |
| **\|obs−decoded\|** | **7.9e-10 / 2.7e-10 / 3.3e-8 / 1.1e-8** |
| \|obs−display\| | 6.99e-2 / 1.50e-1 / 6.99e-2 / 1.50e-1 |

→ 运行二进制走的是 **decoded 基准平面**；E-1 的「−8.6% 首拖、逐代累积」根因已消除。
代码亲核：三处调用点（`EditorAreaView.swift:160/187/600`）全部经
`CropToolRotation.commitFrameSize(decoded:display:)`（`CropToolRotation.swift:100-108`，
decoded 恒胜出）；`PipeCoordinator.decodedFrameSize()`（:2158-2166）单源。
**旋转手柄/滑杆两入口**与 auto 共用同一 commit 缝（同函数、同 frameSize 参数），
本轮虽未能以合成拖拽驱动（见 §七），单缝性质使域修正对其同构成立。

**undo ×2 序（同批）**：undo#1 → crop 回 (0,0,1,1) 而 rotation 仍 −0.4585（先撤框）；
undo#2 → rotation 回 0（后撤角）——LIFO「先框后角」实测在位。

## 二、M-1 修复验证 — PASS

**判据构造**：在 **crop 非全幅 + flip=5（SWAP_XY）** 激活态画一条导线，把存值与该点击
经「display → crop⁻¹ → flip⁻¹ → upright 输入帧」的独立复算比对（这条链里 flip 会
把 x/y 换轴，任何漏掉 post-upright 腿的实现都给出完全不同的值）。

运行态：flip=5；crop 同上；rotation=−0.4585 → upright 输入 span=(9554,6411)；
display= crop 窗 6302×9330.5 px；fitted rect=(459.9,65.5,508.2,752.5) pt。

| 端 | 观测存值（sidecar） | 独立复算预言 | 偏差 |
|---|---|---|---|
| a | (0.7365280, 0.7669312) | (0.736528, 0.766930) | 0.0 / **−0.01 px** |
| b | (0.3004599, 0.7369448) | (0.300460, 0.730179) | 0.0 / 43 px（≈2-4 pt，合成 release 坐标伪影） |

→ 存值 **ax≈0.736** 是换轴后的输入帧域；旧通道（pre-upright compose vs decoded）或
无 flip 域都不可能给出该值。**M-1 修复在 crop+flip 激活态成立**，画线落点与点击一致
（fig: `m1-armed-crop-flip-state.png`）。语义迁移注记（旧档 pre-upright 非中性时存值
含义变）与 DECISIONS 申报一致。

## 三、M-2 / M-3 / m-1

| finding | 实测 | 判定 |
|---|---|---|
| **M-2** 第 5 条拒 toast | guides=4 后再画：**无第 5 条入册**（仍 4）+ 底部 ToastBar 显示 **「已达导线上限——最多四条。」**（`m2-cap-toast.png`；键为 xcstrings zh 值，非裸键）；约 4s 自动消失 | PASS |
| **M-3** 选中态 | ①新画线后无选中（细线 1.5pt/0.7α）；②点线体 → 粗白 2.5pt（`m3-tap-selected.png`）；③拖端点后 → 该线粗白选中（`m3-drag-selected.png`） | PASS |
| **m-1** | `CropFitAngle.swift:38-44` 已披露 upstream `MIN_CROP_FRACTION = 0.02` vs 本产 0.01 + 承接理由 | PASS |

## 四、基础回归

| 面 | 实测 | 判定 |
|---|---|---|
| 90° 两方向 | CW 两次：flip bits **5 → 3**（rot180），视口倒置；侧车 orientation 同步 | PASS |
| 位持久 | quit → 新实例重开同图：orientation=3、rotation=−0.4585、crop 四值、guides(1)+mode off、items=9 **逐项存活**（`regress-rot180-relaunch-persisted.png`；`gate-final-sidecar.json`） | PASS |
| undo ×2 序 | 见 §一（先框后角） | PASS |
| off 态零观感 | off → guided → off 三态截屏，视口区差分：off vs off(again) **mean 0.0 / max 0 / >8 像素 0**（逐字节恒等）；off vs guided mean 18.40 / max 255 / 1,125,586 px | PASS |

## 五、新发现（2 minor，均非阻断；建议入修复批）

### N-1（minor）导线端点拖拽 release **不提交**（live-only，下一次离散提交才携带）

- **实测**：拖 guide#1 上端点（0.2492→0.3045 位移）→ release 后 3/6/9s 读 sidecar：
  `by` 仍 0.24916869205841333、history items 7→7。随后绘制第 3 条导线的一次提交
  才把该端点值带入（by=0.3045）——即端点拖拽**没有自己的提交**；拖完立即关图即丢失，
  且 undo 无该步。
- **根因（代码）**：`UprightGuidesOverlay.swift:136 release()` 先 `dragging = nil`，
  随后只处理 `pending`，端点拖拽分支恒 `return false`；视图侧 `:260/:265` 仅
  `changed == true` 时 `onCommit` —— live 值（setLiveParams）因此永不落为该动作的 item。
- **修法**：`release()` 返回「dragging != nil || pending 落地」；或视图侧改按
  「release 前后 guides 列表不等」提交。单点、低风险，建议带一法回归
  （端点拖拽后 sidecar 即含新值 + 一条 history item）。
- **定性**：M-3 的修复只覆盖「选中态回写」，未覆盖该提交门；双路 lane 的模型级
  测试（guides 数组就地变更）看不见视图的 `changed` 门。若 orchestrator 将
  「拖端点必须持久」定为硬 AC，可升 error；否则 minor。

### N-2（minor）rotate/straighten 重拟在 flip ≠ none 时**未换轴**

- **实测依据**：§一 的观测 crop == **未换轴**（decoded/旋转帧）闭式；而 flip=5 时
  crop op 的输入帧轴已交换（V50：flip 16 → crop 24.5；`CropModule.iopOrder = 24.5`），
  在 flip 帧内正确的边距应是它的**转置**（L/T 0.0117/0.0085）。
- **根因**：`CropToolRotation.swift:208` 的 `rotatedToCrop` 输出域 = 旋转 AABB
  （pre-flip），但 crop 记录实际由 post-flip 帧解释；漏斗不读 flip bits。
- **影响**：近全幅/对称 crop 时边距差 0.3%（不可见，本轮即此形）；**非全幅/非对称
  crop + 90° flip + 角度变更**时重拟窗在 flip 帧内转置（偏置；clamp 后可能贴边不严）。
  无数据损坏（crop 仍是合法分数）。
- **建议**：桥 I/O 按 flip bits 交换轴（或漏斗显式拒绝 flip≠none 并 toast），补一法
  「flip=5 + 非全幅 crop + 10° → crop 在 flip 帧内 == 转置闭式」。

## 六、双路对账（逐条一句 + 路由）

| 项 | 现状复核 | 路由 |
|---|---|---|
| 路 1 minor-1（BUNDLE-MAP `APP 6` vs 实测 5） | **已消**：现行为 `APP 8 UprightGuidesInteractionTests.swift`，文件实测 8 法（修复轮 +3）逐值吻合 | 关闭 |
| 路 1 minor-2（`UprightMath.vpError` 死代码） | **成立**：全仓仍零调用（App/Core/IOP/Tests grep 唯一命中 = 定义行 :115） | 下批清理或补「保留待 auto 模式族」头注；不阻断 |
| 路 2 obs-1（判等门量纲措辞） | **部分消解**：DECISIONS 括号已写「6e-6 px > 1e-6 px 门」；首句仍为「1e-6 归一门」——按括号读法无歧义 | 下批一词订正「1e-6 px 门」；零行为影响 |
| 路 2 E-1 | **修复关闭**（§一） | 关闭 |
| 路 2 M-1/M-2/M-3/m-1 | 修复逐条实测（§二/§三） | 关闭 |
| 路 1 两 minor 之外 | 无新增对冲项 | — |

## 七、局限与透明度（合成输入；不冒充产品结论）

1. **旋转手柄/拉直滑杆的拖拽提交未能实机驱动**：坐标拖拽在 crop overlay 手柄上
   全部未命中（按截图检测框 + 渲染几何算出的手柄位，9-15pt 内无响应，含全新实例
   首动作）；AppKit-backed `Slider` 拖拽可改 live 值（19.9° 可见）但
   `onEditingChanged(false)` 未被合成事件送达（无独立提交；该 live 值随后被下一次
   离散提交携带落盘——sidecar rotation=19.875 出现在 flip item）。判为合成输入伪影。
   E-1 的域修正因此走 **auto straighten 入口**（同漏斗同缝）+ 代码亲核 + undo 序三重承载。
2. **TIFF raster 黑屏观察（与本批无关）**：合成 8-bit TIFF（1200×900；无 ICC 与嵌
   sRGB ICC 两版）视口渲染为黑（decode 日志正常，`default look skipped (raster
   document)`）；RAW 正常。stock `Tests/Fixtures/TiffRaster` 件未触。建议另立
   小项以 stock 件复核（可能为既有 raster 路径问题，非 M9-3 回归）。
3. `-la_editor_probe` 探针末行把 `displayTexture` 置 nil（探针既有行为），走查需
   「返回图库 → 双击卡片」重载一次；不影响判据（sidecar/渲染均为真实产线面）。
4. 探针临时工程污染 `library.recentProjects`（9 条 temp 路径）——已清 defaults；
   下批可考虑探针不写 recent。

## 八、证据清单（`omp-evidence/`）

| 文件 | 内容 |
|---|---|
| `build.log` | BUILD SUCCEEDED（07:13，晚于 4809f227） |
| `monitor.log` | RSS monitor（零 kill） |
| `omp-verification.txt` | 全部原始观测 + Python 独立复算逐值 |
| `e1-slider-live-19.9-uncommitted.png` | 漏斗 live tick 实况（19.9°）+ crop 框 |
| `m1-armed-crop-flip-state.png` | crop+flip 激活态 / 导线工具武装面 |
| `m2-cap-toast.png` | 第 5 条拒 + 「已达导线上限——最多四条。」 |
| `m3-tap-selected.png` / `m3-drag-selected.png` | 点选/拖拽选中的放大对照 |
| `offA/offB/offC-upright-*.png` | off→guided→off 三态（机检差分 0 / 18.4） |
| `regress-rot180-relaunch-persisted.png` | 90°×2 + crop + guides 重开存活 |
| `gate-final-sidecar.json` | 终态 sidecar verbatim（orientation 3 / rotation −0.4585 / crop / guides / items 9） |

## 九、建议（给 orchestrator）

1. **M9-3 可签核**：E-1（唯一 error）修复经数值门证明；M-1/M-2/M-3/m-1 全闭环；
   双路 minor/obs 逐条落路由。
2. 修复批（小）纳入：**N-1**（端点拖拽提交门，一行 + 一法）、**N-2**（flip 换轴 /
   显式拒绝 + 一法）；顺带 **路 1 minor-2**（vpError 清理或注记）、**路 2 obs-1**
   一词订正、`BUNDLE-MAP` 已消无需动。
3. 走查 MANIFEST ① 请按路 2 建议补「二次拖动 + 角度回 0 复原」核对点（本轮以
   19.875° 旧角数值门等价覆盖）。
4. TIFF raster 黑屏观察另立小项（stock Fixtures 复核），勿混入 M9-3 账。

—— 终审：omp（独立于双路，未读对方过程证据之外的实现细节；全部结论以本轮实测为准）。
