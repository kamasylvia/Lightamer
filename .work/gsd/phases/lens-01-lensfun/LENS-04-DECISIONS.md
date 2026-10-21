# LENS-04 DECISIONS — plan L4 裁定记录(process version 裁决表正本)

> 正本 = CONTEXT.md(D-LENS-3 + X3);RenderProcess.swift:25-44 bump 纪律三问。

## process version 裁决表(八项 × 三问;T2 正本)

裁决汇总:**全部默认中性 → 不 bump**(RenderProcessVersion.current 恒 v1;RenderProcess.swift 零 diff = 机检面)。

| # | 变更 | ①look-changing? | ②默认中性证据 | 裁决 |
|---|---|---|---|---|
| 1 | L2 enable/三 toggle | 否(nil=true 直通) | gated 直通 + LensPerCorrection all-nil face | 原位 |
| 2 | L2 auto-apply | 否(默认 false 不触发) | LensAutoApply 缺席=false | 原位 |
| 3 | L2 scale | 否(nil=false auto/1.0 user = 恒等) | LensDefaultNeutral + LensScaleGolden scale=1 | 原位(**D-L2-1 偏差是中性的前提**) |
| 4 | L3 projection | 否(rectilinear = 无前缀) | LensDefaultNeutral 投影前缀臂 + coincident face | 原位 |
| 5 | L3 TCA ROI union | 否(resolved 面默认不达) | 默认 .off 不走 lensfun ROI 面 | 原位 |
| 6 | L3 数据分发 | 否(数据面,非渲染) | seed 只供给匹配源,渲染仍需显式 source=.lensfun | 原位 |
| 7 | L1 匹配硬化 legacy 档 | **潜在(review M3)**:snapshot-nil 旧 `.lensfun` 档 live resolve 命中→miss = 校正消失、系数变 = 观感变 | 三问① = 部分是——但该面 = **缺陷修复**(crop gate 失效期误配的校正本就不该在) | **原位修(③ crash/缺陷修复律)**:不 bump;恢复 UX = 面板 Re-match + browser;快照档(T1 后)免疫 |
| 8 | L4 snapshot | 否(nil 默认 = 字节同 legacy) | LensSnapshot 零漂移负测 + 消序双臂 | 原位 |

## D-L4-1 bake 时机 = 同步(option A)

reloadDefaults auto 臂内**同步匹配 + bake**(与 source 翻转同一 commit);browser 选型同构。理由:后置(首帧 identity 一瞬)引入「首帧观感闪变」+ 二次 commit 复杂度;同步的代价 = reloadDefaults 变重(首匹配 ~1ms 实测,memo 前 1ms 级)——可忽略。**无双路径**。

## D-L4-2 快照形态 = 标定提取(kernel-ready 的否定)

快照存**分辨率无关标定提取**(标定行 + 元数据),消费时经虚拟 entry 以当前分辨率重跑 resolve 数学。**否定 kernel-ready 系数形态**:LensKernelParams 系数含 NS·HW 折叠(分辨率相关),kernel-ready 快照在其它平面尺寸会错渲染——提取面才是 H-L2「DB 更新不改渲染」+「尺寸无关」双门的正确形态。标定结构 Codable/Hashable 化为伴随面。

## D-L4-3 dbTag 语义落地(X3/review m2)

dbTag = install 时 sorted per-file manifest SHA-256 前 16 hex(store 面);commitParams hash 输入 = **strip-on-hash 变体**(dbTag encode 前 nil)→ DB 更新(dbTag 变)零 cache 抖动;标定漂移仍翻 hash(真失效)。paramsData 持久面携完整 dbTag(审计可溯)。Params.snapshot = **internal**(App 零触值面;面板经 bakeCommitted/rematch/clearSnapshot 三 store 面)。

## D-L4-4 --all G3 冷页平台偏差(环境)

全套轮启动时 G3 交换 ~5.0G ≥ 4GB 门(前序七 bundle 轮推上去的惰性冷页,30 分钟仅降 100MB;L0xx-e 校准注记:静态 swapused 不反映压力,失控病理由 G2/MEMFAIL 承担)。**偏差放行依据**:G1 零并发重活、G2 可用内存 85%、G4 磁盘 30GB、orchestrator 派发指令预授权 + MEMFAIL 机检兜底(>8G 即 kill)。实测三轮峰值 7657MB 全门内、零 MEMFAIL、三轮同值——放行正确。

## D-L4-5 Library flake 作废轮(环境型)

Round 2 首跑 `LibraryThumbnailBridgeTests.testPrioritizeReordersQueuedProductions` 1 failure(thumbnail 桥队列优先级时序)中断全套(rc=1)。**与 lens 批零交集**(Library 域,lens 零触;本批未触该域任何文件);单测隔离 3 次复绿。处置 = 恢复协议(M2-11 先例):作废轮弃用,干净重跑计三轮同值。LESSONS 候选:时序型 flake 的作废-重跑判定(单测 3x 复绿 + 域交集检查)。

## 偏差清单

- ΔN +26 越带(+12..16)——SUMMARY 申报(落域调整:cache 4 法挂 T3 名义实为 T2 断言延伸)。
- 全批 ΔN +97 越带(4050..4079 → 4088,越 +9)——全批 SUMMARY 申报。
- RawLab 抽查延后供件——evidence repo 记录(T4)。
- --all G3 偏差放行——D-L4-4。

## 修复批裁决追加行(2026-10-20,B-1/M-1 修复;八项表延续)

| # | 变更 | ①look-changing? | ②默认中性证据 | 裁决 |
|---|---|---|---|---|
| 9 | B-1 `isNeutral` lensfun 激活臂 + M-1 fisheye 公式重转录 | **潜在**:零滑杆 lensfun 文档渲染 identity→校正;fisheye 折叠系数变 | 三问① = 是——但该面 = **缺陷修复**(③ 律,同第 7 行先例):B-1 面 = 04-04 以来从未生效过的路径(恒 identity blit,无已交付观感);M-1 面 = 批内未签核交付的误标公式(无存量文档)。渲染前原位修,零冻结义务 | **原位修:不 bump**(RenderProcess.swift 零 diff 机检随修复批复核);行为级证明 = 修复批 golden 双发 |
