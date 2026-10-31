# R9 修复批：胶片档 × 几何编辑渲染黑洞（M-1 major，omp 执行 lane）

你是 R9 修复批执行者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文，commit 英文。当前 HEAD = `5a1729b6`，全套基线 **4438/34/0**。产品 commit `fixes #N`（`gh issue create` major 级新建）。

## 病灶正本

`.work/gsd/phases/r8-repairs/R8-ACCEPTANCE-OMP.md` §M-1 + 30 件证据（omp-evidence/，你上轮自己的发现）：
- **表型**：启用胶片模拟文档（film record 在册）→ 几何编辑（CW90）→ 提交/sidecar 落盘成功 → **视口全黑 35s+ 不恢复**；胶片卡三值 NaN；undo 存活仍黑（持久坏态）；quit 重开 direct-load 3 分钟+ `rendered=NO/isDecoding=true` 黑。
- **对照**：同链无胶片 record 全正常；胶片启用前渲染正常——空洞仅在「film record × 几何编辑」交集。
- **上下文**：R8 刚修 `forwardWalk` 尾 `roi = roiWalk`（协商终帧发布，非几何链已验）；候选方向 = film leg 的 walked 帧协商 / seed 键 / solve 缓存 / 启用落盘延迟写腿差异——「不能排除修复只盖一腿：film leg 的 walked 帧转置行为仍错」。

## 任务

1. **机制定位**：film sub-run（FilmMethodBox.runContext / film_subrun fused kernel / runTerminalTails 共享序）在几何激活转置帧上的行为。候选：①film sub-run seed/键含帧形假设；②solve 缓存键转置帧撞缓存；③film leg 起步平面形 vs negotiated 帧错配（R8 同族另一条腿）；④solve 在转置帧产 NaN（256-bin 统计直方图转置帧行为）。逐一读码 + 探针定罪（file:line）。
2. **修复**：最小缝对齐 R8 语义（协商终帧一致发布到所有 sub-run 腿）；NaN 另修（solve 输入守卫/统计窗修正）。封存面 17 件零 diff（PixelPipe 触碰逐 hunk 申报先例；film 腿核心非封存件）。
3. **回归**：确定性复现「film record + 几何编辑」黑屏链测试（修前红证据）+ NaN 守卫负测 + 非几何零漂移负测。
4. **实机验证**：原样链（启用胶片 → CW90 → 重开）渲染恢复非黑 + 胶片卡数值正常。
5. **全套**：guard（**G4 透明越门先例：Data 卷 ~21G 现实基线，free 70%+ 无 swap 压力，DECISIONS 追记；起跑前清 /tmp 残留与 Intermediates 尽人事**；`--monitor 21600 &`；SPM 失败 `-disableAutomaticPackageResolution` 离线先例）；预期 4438/34/0 ⊕ ΔN（+2..5 → 4440..4443）。
6. **域内自审（新阵容层）**：修复+实机验证后，派出自己的 omp subagent review lane（`omp -p` 实例，隔离白名单 = 只读产物不读你的中间态，任务书含机器纪律）审你的修复；自审发现回注自修；自审收敛后收口。

## 纪律

commit-per-task；封存面申报纪律；M8/M9-2 光谱面零回归（BWSpectralGolden/双臂哨兵必须绿——film leg 是其宿主）；zh-audit 若触文案；GUI 探针用后清零 defaults。

## 产出契约

`phases/r9-repairs/R9-{SUMMARY,DECISIONS}.md` + 回归与全套证据 + issue + commits。stdout 最终消息一次性完整输出。
