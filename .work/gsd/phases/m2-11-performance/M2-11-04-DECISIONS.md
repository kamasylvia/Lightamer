# M2-11-04 DECISIONS — 三分法口径签注 + 断言两层分工签注（wave 4 执行期裁定）

> 编号 §1..5；与 SUMMARY 偏差节互引。裁定原则 = plan 已定裁决不重开
> （OQ-1-A / D-3 / KD-1..3），本文件只签注执行形态与边界。

## §1 三分法口径签注（OQ-1-A 落地形态）

- **口径①（GUI 稳态 ≤3GB）= 实测层**：KD-1 场景脚本三轮，主判据
  phys_footprint（`/usr/bin/footprint` CLI，macOS 27.0.1；与 AGENTS.md 资源监控
  /SPIKE 同族口径），辅读 ps resident。T0（编辑尾）与 T60（静置 60s 后稳态）双
  读，**门判据 = T60 中位**（clearCaches 60s sweep 走完后的稳态——KD-1 原文语义）。
  B 案（FULL 足迹字面 3GB 硬门）/C 案（3GB 降记录档）维持禁复活。
- **口径②（FULL 瞬态）= 断言维持层**：`testNLMeansFullFootprintBudget`（bilateral
  FULL Δfootprint <3GB D-C1 门）+ `testCompositeFullWindowedPlaneSizes`（窗口化
  O(视窗) 精确台账）+ `testFullToneEqualMemoryBudget`（PreviewChainPerfTests:178）
  零触碰零新增——「维持」的负证形态 = diff 零命中 + IOP 全量在册绿。
- **口径③（宿主 8G）= 运行门负证层**：`Scripts/test-direct.sh` 零 diff，
  `RSS_LIMIT_MB=8192` 实体不变；perf.md §PERF-02 口径③行写明「8G = 运行门
  （MEMFAIL 机检）非内存 SC 门」+ SPIKE 指针，防后续误读。

## §2 断言两层分工签注（KD-2① 单测层 vs KD-1 实测层）

- **单测层（T2）钉机制上界，进程级数字不在单测断言**：常量 pin（defaultBudget
  3GB / evictTarget 2GB / floor 公式在生产常量下解析为 evictTarget）+ 注入阈值
  稳态 no-op 腿（预算内零 churn）+ 越界逐出腿（floor 语义精确台账：1000 总量、
  trigger 999 → 4 planes/400B 逐出，resident 600 落 [kept 500, floor 666] 带内，
  kept PREVIEW 双存活）。**3GB 全进程数不进单测**——KD-2① 原文，进程级归 KD-1。
- **实测层（T1）钉进程数字**：稳态中位 1975MB ≤3GB。
- **两层互证关系**：单测证「超限即逐出 → footprint 有界」（机制保证），实测证
  「稳态在界内」（实际行为）——GUI 会话未越界时触发态证据不可得（§4），边界由
  单测层补齐，缺口闭合（RESEARCH §A.2「clearCaches 分层在码无数字账」的数字账
  由两 层共同落账）。
- **首轮测试失败修正（设计内）**：初版 (c) 腿误设「逐出全部可逐出面」预期
  （planesEvicted==5/bytesFreed==500/resident==500）——hysteresis floor 语义下
  sweep 在 ≤floor 即停（600 ≤ 666），预期改为 floor 语义精确台账（4/400/600）。
  测试语义不变（有界性），账目对齐实现语义（`enforceBudget` guard 循环）。

## §3 GUI 驱动通道签注（KD-1 场景脚本）

- computer-use SDK 主 agent 专属政策拒 subagent（02 波 T6 同款）→ 回退面 =
  **probe 缝（`-la_editor_probe`，DEBUG-only 既有自动化缝）+ System Events AX
  （菜单/键盘）+ CGEvent（double-click/scroll/drag，驱动源随档
  `profile/cgdrive.swift`）**。全程真实 GUI app 真样张（checker E1 真链）。
- **slider drag 发现**（L068）：合成单击不改值——首轮 click-at ×10 全空点，截图
  复核抓出后改 drag 序列（10 drag 每枚实改值，色温 6504K→23521K→…→4201K 截图
  链在 MANIFEST）。02 波「轨道 click-at」的 hitch 场景不核值，与本轮不冲突。
- 场景保真度注记：R1 会话含 AX 通道调试动作（直方图→波形 toggle 一次）——
  R1 T60 2427MB 略高于 R2/R3（1975/1856）的归因注记；中位口径对此稳健。
- 用列 = RAF 100MP（KD-1 任一列口径；60.2MP 交叉列未跑——单列即满足门判定，
  不凑数）。

## §4 机制核验边界签注（KD-1 机制实活）

- **三轮 enforceBudget/evict 统一日志查询零命中**（`/usr/bin/log show` predicate
  `enforceBudget|evict` --info，会话全程窗；`profile/r{1,2,3}-mech.log`）+
  **D-26 toast 零出现**（>500MB 释放才 toast）→ 稳态 footprint 低于 3GB 预算 →
  60s sweep **no-op（设计语义）**。
- **如实注记**：GUI 会话「触发态证据」（触发日志/toast/LRU 逐出计数）在未越界
  稳态下**原理性不可得**——本波负证 + T2 单测层触发态证据（越界即逐出）互补，
  即 §2 两层分工。insert-time LRU（`evictUnderBudget`）无日志面为代码事实
  （PipeCache.swift 无 logger 调用），其正确性由 MemoryBudgetTests 既有
  keep/evict 矩阵承载，非本波缺口。

## §5 执行期偏差登记

1. **probe 缝两 quirk**（零产线影响）：①`NSApp.terminate(nil)` 2/3 轮未生效
   （app 驻留后台，TERM 清理；probe 本体任务已完成——PASS 行在 log）；②
   「grid rows never arrived」间歇 2 次（10s×100 等窗竞态，重试即过）。M2-11-05
   probe 使用方注记：等窗不足或 terminate 挂起时先查进程态再判失败。
2. **plan 指针行号漂移**：`RSS_LIMIT_MB=8192` 实体 :70（plan 写 :59）——M2-11-01
   KD-1 解析器抽取使脚本头注释增长；实体零变化（AC#3 钉常量）。
3. **T2 首轮 3 断言红** → floor 语义修正（§2 末条），修正后 14/0/0；产线零改码。
4. **perf.md 对账尾注随 T2 commit**（`f238a55`）——测试与账同批纪律，先于 T3。
5. zsh 会话 `log` 内建与 `/usr/bin/log` 同名冲突——机检一律全路径
   `/usr/bin/log`（会话级操作事项，非工程缺口）。
