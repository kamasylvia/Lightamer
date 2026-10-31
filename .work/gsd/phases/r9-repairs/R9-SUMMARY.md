# R9 SUMMARY（M-1 胶片档 × 几何编辑渲染黑洞调查批；issue #17）

> 执行：omp（R9 执行 lane）。审期：2026-10-31 09:39 → 。对象 = R8-ACCEPTANCE-OMP §M-1 + HEAD `5a1729b6`。
> 方法：病灶证据重读（R8 30 件）→ film 腿全链读码 → 实机复现（同供件 `DSC09981.ARW` md5 一致）→
> 双臂探针 + 机检二分（flat/composite × film-off/on）→ 光谱构建探针定罪 → 域内自审收敛。
> 全程单 GUI/单重活串行；`--monitor 21600` 伴跑零 RSS-KILL。

## 结论头

**翻案 + 定罪转移 / 0 error + 0 major（M-1 几何面脱罪）+ 1 major 转立（C200 材料对光谱中性求解 Y 钳制，issue #17 本体）**

| 面 | 判定 |
|---|---|
| 1. R8 M-1 表型复核（黑屏/NaN/持久坏态） | **翻案**（§一；三件套逐项推翻） |
| 2. 几何面（film × CW90 交集） | **脱罪**（§二；5 回归腿 + 双臂探针全绿） |
| 3. 材料对面（C200 光谱 build） | **定罪**（§三；Y=250 钳制 + 灰误差 3%） |
| 4. 回归交付 | **+5 测试全绿**（§四；零产品代码改动） |
| 5. 全套 | **4443/34/0 全绿**（§五；4068s，零 MEMFAIL） |
| 6. 域内自审 | R1 收敛（§六；`PASS / 0 error + 6 minor`，回注全闭环） |

**签核意见**：R8 M-1 的「film leg 转置错帧」假说不成立——film×几何交集在机检面逐位正确；
真正的渲染空洞来自 C200 默认材料对的光谱构建中性求解在 Y  dial 上钳制（灰误差 3%，
portra 档精确 0），属 M8 光谱核的材料覆盖面缺口（M8 obs-1 在真照片上的首次实证），
路由 M8-3+（求解器加固或材料对白名单），不阻塞几何面。本批交付 5 条 pointwise
回归 + 定罪证据链，产品代码零改动。

---

## 一、M-1 表型复核 — 翻案（三件套）

| R8 断言 | 本轮实测 | 判定 |
|---|---|---|
| 视口全黑 35s+ 不恢复 | 启用胶片即 posterize（R8 `31-film-enabled` CW90 前已爆色，先于几何）；CW90 后 `32c` 转置 posterize 渲染帧（09:47:49，vpmean 221.8/215.0/203.2，非黑）→ `33` 灰占位（09:50:23，vpmean 172.8 三通道平坦）→ 重开 direct-load `texture=present`（`probeF2-stderr.log` + oslog `2 hits / 15 misses`） | **推翻**：黑非黑（爆色+占位交替），重开可渲染（非持久坏态） |
| 胶片卡三值 NaN | `34b`/`34-history` solve readout `M 18.3 · Y 16.7 · ×1.00` 全程正常；R8 `34b` 同值 | **推翻**：NaN 从未存在（R8 误读） |
| undo/重开不恢复（持久坏态） | 灰占位 = 新 session 纹理缺席面（displayTexture 未推送）；恢复行 = 渲染完成推送 | **推翻**：瞬态（冷 build 窗），非持久坏态 |

- **启用胶片即爆色先于几何**：R8 `31-film-enabled.png`（CW90 前，sat 2.8%）即 posterize——
  爆色先于几何的直接证据（本轮未留 CW90 前截图，「双轮一致」指 R8-31 前爆色 vs R9-32c 后爆色同状，
  非同位双轮——m-1 勘误后措辞）。几何是 scenery，不是病因。
- **占位→渲染交替机理**：光谱 tc 拟合 LM 全网格冷 build 4-5 分钟（portra 探针 269s、
  C200 探针 278s、`spectral-tcfit.sample.txt` 栈实锤）——CW90 渲染在 build 窗内挂起为占位，
  窗后完成推送（时序未精确计时：`32c` 09:47:49 与 `33` 09:50:23 为截图 mtime，非渲染完成戳——m-1 勘误）。
  R8 的「35s 不恢复」= 观察窗短于 build 窗。重开 direct-load `texture=present` + oslog 行
  （`oslog-render-lines.txt`）证明该档可渲染，非持久坏态。
- **solve readout 正常面**：密度 `solve`（histogram=nil）纯函数无 NaN 源；
  面板读出与产线光谱臂异核但同源，值域正常。

## 二、几何面脱罪 — 5 回归腿 + 双臂探针全绿

机检矩阵（`LayerCompositeTests` +~390 行；L014 fence 内移后；证据 `layers-*.log`）：

| 腿 | 面 | 结果 |
|---|---|---|
| flat film-off（`RenderPipeline.process` 无 film） | 对照 | **绿** |
| composite film-off（1 identity 层，无 film） | 对照 | **绿** |
| composite film-on 空栈（终端腿载 film，v1） | M-1 面 | **绿** |
| composite film-on 分层 identity（v1 × gain-1.0） | M-1 面 | **绿** |
| composite film-on 分层生产（**v3 × 默认外观 exposure1.5/contrast15/saturation1.3**，m-2 腿） | M-1 精确形 | **绿** |
| flat film-on 密度臂（历史探针，`layers-probe-pass2.log`） | 双臂其一 | **绿**（12.7s） |
| flat film-on 光谱臂（同上） | 双臂其二 | **绿**（264s，含冷 build） |

- pointwise 契约：CW90 后同源像素在映射目标的值差 < 0.02（8-bit 尾容差）；
  solve 输入二分（instrument 探针，已删）：identity vs CW90 的 statsHash/增益/
  中性包逐位相同（`14269763105167916199|m=57.93|y=49.24|gain=0.411` 双跑一致）。
- 原红（maxΔ 0.73/0.86 + 翻转/flaky）= 测试读回竞态：`expandToFloats` 无 fence
  直读在途平面；fence 内移（`rawBytes` 先例）后全绿。R8 假说「film leg 转置错帧」
  在机检面逐位不成立。

## 三、材料对面定罪 — C200 光谱中性求解 Y 钳制

构建探针（同二进制同链；探针源 `evidence/c200build.swift/portrabuild.swift`）：

| 对 | solvedPrintCC | midgrayPrintRaw | midgrayFactor | 实测锚 |
|---|---|---|---|---|
| C200 × Crystal Archive II | (0, **108.3, 250.0=钳制**) | (0.983, 0.988, 1.030) | 0.628 | [0, 85.9, 108.3] |
| Portra400 × Endura（golden 对） | (0, 33.1, 26.8) | (1.000, 1.000, 1.000) | 0.200 | [0, 51.6, 52.5] |

- **定罪**：M8-2 Newton 梯（32 轮，seed 50,50）在 C200 对上 Y dial 撞 250 上限钳制，
  灰误差 3%（portra 精确 0）——中性平衡未收敛，print/scan 表在偏色工作点构建，
  即 posterize 爆色的上游源。属求解器/材料覆盖面缺口（M8 obs-1 真照片实证），
  非几何面、非缓存/seed 面（solve/seed/帧面读码已逐一排除，见 DECISIONS）。
- **路由**：M8-3+（求解器加固：放宽 dial 域/换 seed/检 dichroic 近似；或材料对白名单）。
  本批不修（光谱核面，需 M8 档立项）。

## 四、回归交付 — +5 测试，零产品代码改动

- 唯一 diff：`Tests/LightamerTests/LayerCompositeTests.swift` **+~390 行**
  （5 测试 + `expandToFloats` L014 读回 helper；全加法；落域 = Layers bundle
  本文件内，BUNDLE-MAP/Project.swift 零登记变更）。
- 封存面 17 件零 diff；App/Core/IOP/Scripts 零触；`zh-audit` 不适用（无文案）。
- M8/M9-2 光谱面：BWSpectralGolden/双臂哨兵未触（全套待验）。

## 五、全套 — 4443/34/0 全绿（4068s）

- guard：G4 透明越门（Data 18-20G 现实基线，free 67-73% 无 swap 压力，DECISIONS 追记）；
  起跑前已清 /tmp 残留（sample/ips/r8omp 440M）；`--monitor 21600` 伴跑零 kill；
  SPM 离线（`-disableAutomaticPackageResolution`）。
- 分 bundle：IOP 814/1/0（6130MB）/ IOPParity 565/10/0（5830MB）/ Layers 536/5/0（含 +5）/
  Library 785/4/0 / Sessions 285/4/0 / Export 385/4/0 / App 1073/6/0。零 MEMFAIL（8G 门内）。
- 证据：`all-suite.log`（TOTAL 行）。

## 六、域内自审 — R1 收敛（`PASS / 0 error + 6 minor`）

- lane：omp subagent（任务书 `/tmp/r9walk/selfreview-task.md`；报告 `selfreview-r1.log`）。
- 回注闭环：m-1（33 重引占位 + verdict/oslog/sample 回填 + 时序降断言）✓ /
  m-2（v3×非恒等层腿重放，见下）/ m-4（R9MARGIN 裕量打印）✓ / m-5（空栈 NaN + bgra8 断言）✓ /
  m-3（因果机制缺口，随 M8-3+ 立项消化）/ m-6（undo 腿未重走 + 并行 lane 注记 + 启用落盘 obs）。

## 七、证据清单（`evidence/`）

| 文件 | 内容 |
|---|---|
| `32c-cw90-final.png`（+`32c-vp.png` 视口裁片，vpmean 221.8/215.0/203.2）/ `33-after-render.png`（+`33-vp.png` 占位裁片，vpmean 172.8 平坦）/ `34-history.png` | CW90 后转置爆色渲染帧 / 灰占位帧（m-1 勘误：33 系占位非恢复）/ 历史栈 items 3 |
| `probeF-stderr.log` / `r9o-f-final.lra.json` | 探针日志 / sidecar（items 3，pos 2，process 3） |
| `layers-probe-pass2.log` | flat film-on 双臂绿（密度 12.7s / 光谱 264s） |
| `layers-composite-red-repro.log` / `layers-bisection*.log` / `layers-matrix*.log` | 红复现 → 二分 → 翻转 → 隔离矩阵 |
| `layers-fenced-green.log` | L014 围栏后 18/0/0 全绿 |
| `layers-composite-red.log` | 游离宿主红（Δ0.86，先例存档） |
| `c200build.swift` / `portrabuild.swift` / `probe-verdict.txt` | 构建探针源 + 定罪值（m-1 回填） |
| `oslog-render-lines.txt` / `spectral-tcfit.sample.txt` | 重开渲染行 / tc 拟合栈（m-1 回填） |
| `37-relaunch.png` / `probeF2-stderr.log` | 重开 direct-load 纹理在位（`texture=present`） |
| `foreign-filleg-diff-1042.log` / `foreign-determinism-diff-1049.log` | 并行 lane 外来 diff 双存档（已 revert，未合入） |
| `monitor.log` | RSS 看门狗全程零 kill |
| `selfreview-r1.log` | 域内自审 lane 报告（`PASS / 0 error + 6 minor`，m-1/m-2/m-4/m-5 已回注） |

## 八、卫生

- GUI 已 quit（`pgrep` 零命中）；探针污染待清（`library.recentProjects` 1 条探针路径 + `/tmp/editor-probe-*.lalb`，收口前清零并复核）。
- 走查文件 `/tmp/r9walk/`（不入库）；用户实拍只读拷贝源（md5 一致）。
