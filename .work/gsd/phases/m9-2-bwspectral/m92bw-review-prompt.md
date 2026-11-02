# M9-2 改签批「v0.3.3 BW pack 解码修复」review lane（zcode 独立审核）

你是 M9-2 改签批的独立审核者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。**只读 + 定向测试复跑，零产品代码修改、零 commit。** 全程中文，结论头 `PASS / N error + N minor`。产出报告落盘 `.work/gsd/phases/m9-2-bwspectral/M9-2BW-REVIEW.md`（chunked ≤8KB）+ stdout 一次性完整输出。

## 审核对象

- 产品 commit `339adb33`（fix(m92) 18 文件，fixes #22）+ 账本 `e63ebb3f`；HEAD 应为 `e63ebb3f`（先亲核）。
- executor 汇报正本 = 会话报告要点：产线四件（FilmProfile nullable 双形解码/中位显影列归一、FilmMaterialStore materialPairHash nil-vs-value 折、SpectralBuildEngine/PaperGradeTable nullable 消费、BWPackDecodeTests 4 法）+ 三件遗留修复（BloomTests 行恢复/计数钉 re-pin/BW 分节 7 卷）+ 全套 4533/34/0。

## 审查清单（逐项实测核验，禁轻信报告）

1. **边界**：`git show --stat 339adb33` 与任务域对照（Film*/Tests/Project.swift/BUNDLE-MAP 之外零文件）；`git show --stat e63ebb3f` 全 docs；两 commit 外无未提交产品面残留（`git status` 短查）。
2. **封存面独立机检**：对 `339adb33^..339adb33` 逐件验 17 件封存面零 diff（TerminalTailPolicy/DrtTailAssembly 在 PixelPipe.swift、ExportFormatSpec 在 ExportRecipe.swift 按类型名定位）；RenderProcess.current 恒 3；GrainModule/两 .metal/LibraryProjectController/McpServerController 零 diff；`Resources/FilmProfiles/` 零 diff。
3. **BloomTests 行恢复实证**：Project.swift IOP 数组含 `BloomTests.swift` 行 + 新 `BWPackDecodeTests.swift` 行（纯插入形态）；BUNDLE-MAP IOP 域计数含两者；`grep -c "func test" Tests/LightamerTests/BloomTests.swift` = 6 法在册。
4. **计数钉逐处核**：FilmProfileTests（28→31 / version 0.3.3 / film 22→25 / densitometer set-wide 含 bw→diffuse_visual 分支）；SpectralBuildGolden/GrainGolden/DualArmGolden 三 set-wide 遍历改写与 HEAD 一致；ExposureSemantics manifest 30→33；BW 分节快照 7 卷；anchored 探测面 23 vs 期望 20 的排除逻辑（2302 第三印片 + trix/doublex 无锚种子）——读测试文件核对判定理由成立。
5. **nullable 语义抽查**：FilmProfile.decode 对 `logSensitivity` null 的逐字保留与消费端 null→0；**存量 28 卷形 pass-through 零漂移**——抽 2 个 legacy profile（如 cinestill_800t + 一个黑白）亲跑 decode 比对 hash 或结构断言（定向单测复跑即可）。
6. **materialPairHash**：nil-vs-value 标签折改动仅运行时缓存键（确认不改输出面/不改持久化哈希）。
7. **定向复跑**（test-direct 定向，禁 --all）：`BWPackDecodeTests` + `FilmProfileTests` 两类（guard 后跑，随跑随清）。
8. **ΔN 对账**：4533 = 4443（R9 锚）+ 86（中间批）+ 4（本批 BWPackDecodeTests 4 法）——核对各批 commit 的测试增量可加性（不必逐批重跑，账面核对 + 抽验 BWPack 4 法计数）。
9. **zh-audit 复跑**：`--check` + `--self-test`。
10. **反自取消探针**：任选 2 项 executor 声明，用与 executor 不同的方法验证（如用 grep 而非读文件、用 shasum 而非 diff）。

## 环境事件复核（不动产品）

首轮 IOP 腿 SIGTRAP `libsystem_malloc _xzm_reclaim_force_sync`（LensfunDB 析构中）定为环境型——复看 `~/Library/Logs/DiagnosticReports/Lightamer-2026-11-02-235749.ips` 关键栈，判定「环境型/无 Swift fatal」结论是否成立，记 obs。

## 纪律

- 机器：重活前 `Scripts/machine-guard.sh`；定向测试用 `Scripts/test-direct.sh` 跑法；跑完清场。
- 零 push、零 commit、零产品修改；发现 error/blocking 列 finding 清单（file:line + 修复建议），不自行修复——回注 omp 修复循环归 orchestrator。
