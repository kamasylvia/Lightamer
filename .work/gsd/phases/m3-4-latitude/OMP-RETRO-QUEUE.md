# omp 回溯二次验收队列（M3 收官前置，2026-10-10 用户令）

## 范围
M2-0..M2-11 全 phase + M3-0 + M3-1（三波）+ M3-2（research+spike）+ M3-3（三波）。
M3-4 起走双验收制度；M1 期不在范围（早于 M2 charter）。

## 执行方式（每项）
1. `omp -p --auto-approve --thinking max "<验收 prompt>"`——prompt 含：该 phase/plan 的 ACCEPTANCE 正本路径 + SUMMARY + 三条以上核心证据抽查点（读码/实机 computer-use/定向测试抽样）+ 结论头格式
2. 结论落 `<plan>-ACCEPTANCE-OMP.md`（同目录），PASS/FAIL + 证据引用
3. FAIL → 回注修复批 → 复验；**串行执行，禁并发**（computer-use 单实例）
4. 全部 PASS → 进 M3 VALIDATION（M3-4-02 收口波）

## 清单（执行序）
- [x] M2-0（charter/feature map）
- [x] M2-1 禁用矩阵
- [x] M2-2 图库与项目模型
- [x] M2-3 UI 壳
- [x] M2-4 节点模型 + 七 bundle
- [x] M2-5 调色
- [ ] M2-6 DRT
- [ ] M2-7 蒙版
- [ ] M2-8 版本与历史
- [ ] M2-9 导出
- [ ] M2-10 AI 图库
- [ ] M2-11 性能收官
- [ ] M3-0 立项
- [ ] M3-1 三波（W1 前置批）
- [ ] M3-2 research + spike
- [ ] M3-3 三波（FSIM-01）

> 编排提示：按 phase 粒度回溯（非逐 wave）；phase 内证据以 ACCEPTANCE 正本为抽查主锚。
