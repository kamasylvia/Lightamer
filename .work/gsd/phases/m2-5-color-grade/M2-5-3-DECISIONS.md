# M2-5-3 DECISIONS — LUT 三件套执行签注（2026-09-30/10-01 夜间批）

> plan = M2-5-3-PLAN.md（checker 修正版 87c039d）。执行 = 本 subagent（ZCode）。
> T1-T6 六任务 + 收口批，每任务边界读 config.toml [gsd]（paused=false/auto=true 全程
> 未变）。许可门证据正本 = `evidence/spectral-film-lut-license.md`。渲染管线红线四文
> 件（LayerCompositeDriver/PixelPipe/PipeCacheKey/Lut3dModule）零 diff（`git diff
> --name-only` 机检，见 SUMMARY 边界节）。

## §一 KD 逐条执行确认

- **KD-1（键升级一处承载三件事）**：`installed`/`parsed` 键 = `relativePath`（POSIX
  根相对）。旧行 decode 宽容（`InstalledLut` 增 optional `relativePath`/`subdirectory`，
  synthesized decode 缺字段 = nil）→ init 迁移段从 dict key 推导 → 首次 rescan
  persistRegistry 落盘升级版（幂等有测试钉）。`lutName` 旧引用 = 精确 key 命中 →
  唯一尾段 fallback（歧义 = nil = degrade）；**旧档引用字节零改写**（resolution 层兼
  容 + 面板 `displayKey` 只用于高亮显示）。自愈三段式/blit identity/toast 语义零改动。
- **KD-2（递归 + sanity）**：`enumerator(at:)` + `skipsHiddenFiles` +
  `skipsPackageDescendants`；目录跳过、registry.json 天然不过扩展名过滤。500 文件
  <5s 软上限钉死（实测亚秒）；万文件 = 环境门控探针（见 §六）。
- **KD-3（可配根 + shared holder，checker m6）**：`static let shared` → `private
  nonisolated(unsafe) static var sharedInstance` + `NSLock`（getter 锁内读 +
  `replaceShared(_:)` 锁内原子换），机制内联 LutLibraryStore.swift 零新文件。
  `SharedForwardingResolver`（同文件内嵌 struct）= 长生命周期 module box 的转发面——
  **Registry.swift 一行消费点改引 `sharedResolver`**（§三申报）。坏根 =
  `validateRoot`（isDirectory + 写探针）前置，探针失败不持久化 + Settings 橙色错误行；
  不建 bookmark（12-4 D10 例外不扩展）。
- **KD-4（seeder）**：init 默认根分支（standardized path 相等判定）调
  `seedBuiltIns(from:into:)`；哨兵 = 存在且字节数相等跳过，漂移重拷该文件。可配根
  零自动拷贝（用户数据主权，有测试钉）。**执行形态修正**：source 参数 = URL 而非
  Bundle（测试可造源目录；init 侧从 `Bundle.main.url(forResource:"LUTs")` 取）。
- **KD-5（许可门）**：全流程走通，结论 = **宽松（MIT）→ 资产分支**。两条执行期
  事实更正见 §二。
- **KD-6（收口）**：zh-audit --check 首查即 PASS（新键随手随 commit 入账生效）；
  三查数据入 SUMMARY「观察项」节；GOAL-STATE/AGENTS.md 同批翻账。

## §二 执行期事实更正（不重开裁决，如实修正实态）

1. **「44 张」→ glob 真值 41 张**：plan 预写 44 来自 CONTEXT 清点口径（安装目录根层
   44 项 = 43 张 .cube + `色彩逆向/` 子目录）。CMake glob（Agfa_/Fuji_/Kodak_ 前缀）
   真值 = 41 张（Hasselblad 2 张前缀天然不中）。M2GRADE-07「Hasselblad/色彩逆向不入」
   字面不变。
2. **上游仓不含 .cube——它是生成器**；且 **Alcedo 打包集本就是该工具产物**（安装目录
   文件 TITLE 头逐字记录 `D:\Projects\spectral_film_lut\luts\...` + `LUT_3D_SIZE 65`）。
   → vendored 集 = 上游 v0.18.2 无头重生成（offscreen GUI 驱动，应用默认导出参数 +
   两处显式偏差：65³、BW 配 Kodak 2302 print），**零字节来自 GPL 仓**。上游 stock 目
   录与 Alcedo glob 集 39/41 精确对应（@1600/@3200/Dev_N/High/Low/Alt 全是上游独立
   stock）；Ultramax_500 与 Vision3_500T_5219_3200 上游无对应 → 以最近上游 stock
   （Kodak_Ultramax_400，上游名）收编 + 不造重复表，**最终 40 张**。evidence §四对照
   表 41 行逐行可查。
3. **不主张与 Alcedo 安装目录逐字节一致**（其逐文件导出参数不可考）；一致性主张限定
   = 同工具同版本、同 stock 集（39/41）、同尺寸 65³、同许可。

## §三 front-matter 附录（申报外文件，plan 风险节预授权条款）

| 文件 | 改动 | 依据 |
|---|---|---|
| `LightamerIOP/Sources/Registry.swift` | lut3d 注册行 `LutLibraryStore.shared` → `LutLibraryStore.sharedResolver`（+注释） | KD-3「若既有直引捕获存储实例，收拢 accessor——改动半径限 Lut3d 相关消费点，逐点 grep 申报」；grep 全消费点 = LutPanelView（computed 每次读，无需改）+ Registry 此一处 + 测试 |

其余执行面全部在 front-matter 申报集内（LutLibraryStore.swift / LutPanelView.swift /
SettingsPages.swift / AppPreferences.swift / Localizable.xcstrings / AGENTS.md /
Project.swift / Resources/LUTs/ / 两新建测试文件 + probe 文件 / evidence / SUMMARY /
DECISIONS / GOAL-STATE）。

## §四 测试落点与分期

- LutLibraryRecursionTests（IOPP，终 16 法）按任务分期入 commit：T2 = KD-1/KD-2 九
  法；T4 commit 落 KD-3 四法（切根/坏根/validateRoot/跨根缺名）；T5 commit 落 KD-4
  两法；T6 commit 落万文件探针（env 门控 skip）。与 plan「T4 追加」的分期一致。
- BuiltInLutSetTests（APP，4 法）= T5；SettingsPagesTests +1（T4，键登记断言）；
  GradeEnvelopePerfProbeTests（LAYERS，1 法）= T6 探针。
- **默认根分支的 init seeder 不在测试中执行**（会写开发者真机
  `~/Library/Application Support`）——以 static face 测试 + init 分支 code review 承
  载，SUMMARY 已声明。

## §五 Settings「LUT Library」节落 Cache 页（非新页）的理由

plan 字面 =「Settings 新节」。新增 SettingsPage case 会改写 M2-3-3 D7 钉定的十页断言
面（SettingsPagesTests 两处计数断言）= 重开已定裁决；节挂 Cache 页（存储位置语义宿主
——该页已含 Location 行与「哪些数据在哪」心智）+ 节内文案明示 LUT 是用户数据非派生
缓存。零 D7 面改动，SettingsPagesTests 十页断言零改动通过。

## §六 观察项探针形态（OQ-11）

两探针 = 环境门控（`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless），默认套件 skip：
- **skip 基线变化如实入账：14 → 16**（+2 探针 skip）；executed 侧新增 13 法
  （recursion +7、BuiltInLutSet +4、SettingsPages +1、GradeProbe +1）。
- 100MP 探针第一版未 fence 读钟（base=0.3ms 假数）——L014 教训在探针内复发即修
  （`await fence.completed()`），正确数 = base 156.2ms / 4-grade 1027.0ms。
- 万文件探针 fixture = 微型 2³ 表（枚举/登记开销为主）；真实 65³ 表 parse = 每新文件
  一次性成本，自愈只重解析漂移文件——结论表述限定见 SUMMARY 观察项节。

## §七 Tuist 资源形态发现（沉淀为惯例）

Tuist 4.208 对 `resources:` 里的裸目录字符串**静默忽略**（generate 成功但零登记）；
目录整夹入包必须 `Resource.folderReference(path:)`。Resources/LUTs 以 folder reference
入包（bundle 内保留 LUTs/ 目录，seeder 按夹消费）；真机 bundle 验证 42 项 + 零散落
.cube。此坑记 LESSONS 候选（本批 DECISIONS 先行登记）。

## §八 走查与移交

- T3 走查场景（checker m4）store 级三场景（手动放置子目录 → rescan 收录 / 删除子目
  录自愈 / 缺引用 typed degrade）由 LutLibraryRecursionTests 钉死；**应用内树分组/折
  叠/刷新的目测走查 = Manual-Only 未执行**（交互面），随观察项①一并移交 GUI 验收轮。
- 域盲五件（M2-5-1 移交）本 plan 零触碰（lut3d kernel/params 面零 diff 维持）。
