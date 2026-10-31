# M8-3+ 域内自审 lane 任务书（omp subagent review）

你是 M8-3+「光谱延展批」的域内自审者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。零 commit / 零构建 / 零测试——纯只读 review。

## 审对象

执行链（`git log --oneline` 自查 feat(m83p) T1..T6 commits + 工作区 T7 未提交面）：
- T1：锚 seed + solve 抽取 + clamped 旗 + static_replay.py + REPLAY-RECORD.md
- T2：守恒回退 + 反转路由 + disclosed 面 + 6 xcstrings 键
- T3：五字段 + sidecar v13 + seed 折叠 + bake 不折 + pristine 双面
- T4：B 拆口 + grain 五 kernel + 子层派生 + 量纲桥 + B-track 面板 + NOTICE 3b
- T5：宽 plan + 抽稀三件 + halation/diffusion 表 + 前置腿 + B2 钩 + 分配器 + 面板 + NOTICE 3c
- T6：写腿单行 + t6_probe.py + T6-PROBE-RECORD.md
- T7（未提交）：冒烟 2 法

PLAN 正本 = `.work/gsd/phases/m8-3plus-spectral/M8-3+-PLAN.md`（v2）。
Research 正本 = `RESEARCH.md`。上游正本 = dt spektrafilm `4d1fb6a95b` 树
（git show 必须带树号；HEAD 已无 wide 符号）。

## 隔离白名单（硬纪律）

- 只读产物（源码/测试/evidence/NOTICE/xcstrings diff）；禁读执行 lane 的中间态（omp 日志、lane prompt 落盘说明）。
- 结论头规范：首行 `PASS / N error + N minor`（error = 阻塞收口必须修；minor = 建议修；obs = 观察不计数）。
- 发现按文件:行定位 + 复现/验证路径；禁凭记忆猜——每条 finding 贴证据行。

## 审查维度（与执行自验刻意错开切口）

1. **封存面 17 件**：除 sidecar v13（例外①）外零 diff？PixelPipe 零触？逐件 `git diff` 亲证（封存清单见 PLAN 红线）。
2. **双臂冻结**：v1 两文件（FilmSubRunKernels.metal + FilmFilterPackSolver）零 diff？14 安全档 ULP 带诚实？M8-2 哨兵三件套值亲核？
3. **B 拆口诚实面**：stage_b 退役彻底（零残留引用）？B1/B2 体 = fused B 逐行 verbatim？grain npart=1000 中性占位是否如 DECISIONS 申报般诚实（非静默行为）？amount-0 跳过门与「0 恒等双证明」口径一致？
4. **宽模糊转录**：plan/rows/down/up 与上游 `4d1fb6a95b` 逐行对拍（行号贴出）？TRUE-σ 偏离（无 _yvv_ref_variance）是否显式申报？阈值 100 起步值 vs 「Metal 重标」承诺——T5 commit message 称交点法定了吗？
5. **反转 B 语义**：direct-positive 目标函数（scan 腿比归零）数学自洽？C 收敛在 picker 不可绑 2383/2393（film-support）现实下是否诚实（caption vs 真收敛）？
6. **回退数学**：1D 线搜索单调门诚实（T2 测试曾修门——修后门是否仍有约束力）？gain 折 kernel log-add 与 bake 键诚实（PCHIP 表未动）？midgrayPrintRaw 补偿测量面与渲染面一致？
7. **seed/键面**：recordHash 自动折 seed 是否真自动（FilmTailParams 读 stableHash 亲证）？bake 三槽不折负测是否覆盖 reversal mode（mode 折 print/scan 键——T3 负测数 3 fold 是否含 reversal）？
8. **GPL 纪律**：转录清单（源文件行 + 4d1fb6a95b）完整？NOTICE 3b/3c 行在位？版权头在位？
9. **i18n**：xcstrings 纯插入（`git diff` 零删除行）？zh-audit 双 PASS 可复现（跑一遍）？禁形（插值构键/runModal）零命中？
10. **ΔN 对账**：T1+5/T2+10/T3+10/T4+12/T5+13/T6+0/T7+2 = +52？PLAN 带 +27..40——越带是否申报理由（DECISIONS 起草义务）？BUNDLE-MAP 行内数与实测法数逐项一致？

## 输出

- 落盘：`.work/gsd/phases/m8-3plus-spectral/SELF-REVIEW.md`（结论头 + 分级清单 + 逐条证据行 + 越带/偏差申报复核）。
- stdout 最后一条消息一次性完整输出全文（合并输出，不要拆多条）。
