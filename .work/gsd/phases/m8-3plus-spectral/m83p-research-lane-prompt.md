# M8-3+ 光谱延展批 research lane（omp 执行；纯文本零 commit 零构建）

你是 M8-3+「光谱延展批」researcher。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**纯文本调研：零 git commit、零构建零测试零 GUI**（重活道归 MCP-UQ 批），产物 = 一个 RESEARCH.md 文件，由 orchestrator 收割。

## 任务（正本 = R9 决议 + M8 D-M8-4 挂账族 + 晨审锚定参照）

1. **C200 Y 撞墙修复设计**（R9 定罪：`SpectralBuildEngine.swift:730-747` Newton 梯 32 轮 seed 50,50 域 [0,250]，C200 对上 Y 需 ~2× 越域 → 250 钳制灰误差 3%，tc 冷重建 5 分钟自恢复；R9 m-3 三条不确定性 = 你的输入）：修法设计——域扩展？初值改进？两段式？含对其它 stock 的域外风险评估（28 profile 全扫 Y 需求分布——可从 Resources/FilmProfiles/ 谱面数据静态推算）。
2. **grain/halation/diffusion 接谱设计**（M8 D-M8-4 空间族挂账正主）：三算子如何在光谱核上落地——grain 算子接谱（密度域调制/显影耦合，granularity 标定已在 M9-2）；halation（宽模糊——**dt 宽模糊抽稀优化参照已锚定：`git show origin/main:` 读法，本地树同步**，含 4 个 commits 的拆双 kernel+抽稀+宽度匹配设计）；diffusion。逐算子：数学形态/Metal 落点/性能预算/与 film sub-run 缝的关系。
3. **m-6① + 时长维**：undo 腿未重走 + 2 分钟写腿差异（R9 遗留 obs）——机理假设入研究。
4. **OQ 清单**：研究期新开裁决点逐条列（含推荐值）。

## 输入指针

- R9 定罪正本：`.work/gsd/phases/r9-repairs/R9-{SUMMARY,DECISIONS}.md`（含 m-3 不确定性三条）
- M8 光谱核正本：`.work/gsd/phases/m8-fsim-spectral/`（M8-2-PLAN film sub-run 缝/solve 缓存键/bake 家族）
- dt 参照：`/Volumes/UNITEK/Documents/Development/darktable`（`git show origin/main:` 读法；宽模糊抽稀 4 commits `4d1fb6a95b`/`9fd80e6db3`/`24109e85c1`/`bb3e11cd48`）
- 我方 film 腿现状：`FilmSubRunKernels.metal` / `FilmTailPolicy.swift` / `SpectralBuildEngine.swift`
- M9-2 黑白族（同管线最近交付）：`.work/gsd/phases/m9-2-bwspectral/`

## 产出契约

`.work/gsd/phases/m8-3plus-spectral/RESEARCH.md`：C200 修法设计（含 28 profile Y 需求静态分布）+ 三算子接谱设计 + m-6①/时长维机理 + OQ 清单（带推荐值）。零 commit 零构建。
