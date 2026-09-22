# TASK r1 — Plan 05-05 复审（monochrome 模块）

## 对象
- 产物: `.planning/phases/05-color-denoise-iops/05-05-SUMMARY.md` + 其声明的全部交付
- 代码: `LightamerIOP/Sources/Monochrome/`（filter/apply kernels + module + Registry 注册）
- 提交范围: `git log 51e37f0..ebb417d`（5 commits: 158bb1e/5b55aeb/f34ab40/953c90f/ebb417d）

## 重点（按 plan §验收标准 7 条 + 既有教训）
1. 轨 A parity 4 case × 4 fixture <1e-6（门 1e-3）真循环 + compared>0 + 非空转（grid≠bypass 路径断言）
2. R==G==B / size=100 恒等门；tileHalo=80 / B/px=16 定值 + iscale 折算 + 强制分块 vs 整幅 <1e-3
3. dt 采纳 4/4 byte-identical（`.work/05-05/adoption/`）+ 平场 probe 手算预期
4. 面板色轮 + PanelWiring 48/48 + catalog 5 键 zh/en + a11y identifier
5. 轨 B 双判据；sigma² 钉 CPU 版（:205 2× vs :257 1×）manifest 注记
6. ROI 头注（L020/L021：恒等依据 + 禁 dscIn×scale）；GUI-12 登记核验（moduleList 挤面板）
7. 全套 535/0/3（test-direct.sh）独立复跑

## 已知豁免
- dt probe 定向证据：本机构建树 colorin/colorout stale，probe 钉 BROKEN-route（omp SUMMARY 声明）——各 lane 独立核实该豁免是否成立
- manifest monochrome 节归 05-08 台账轮（05-03/05-04 同口径）
- GUI-12 已立项（05-08 前修），本轮只登记不复修

## 报告格式
`PASS / N error + N minor` 开头 + issues 列表（`文件:位置:问题:建议`）；禁风格意见。
落盘: `.work/matrix/05-05-r1/review/report-<lane>.md`

## CHECKLIST 指针
- `.planning/phases/05-color-denoise-iops/05-05-PLAN.md` §验收标准
- `.planning/phases/05-color-denoise-iops/05-VALIDATION.md`
- `LESSONS.md` L020/L021/L023（ROI/契约）
- `AGENTS.md`「GUI 验收流程」红线
