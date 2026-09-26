# 04-03 Vision 实图抽检记录（pending-manual）

- 合成探针已全绿（VisionDetectTests 4/4）：θ ∈ {−8°, −3°, +5°} <0.2°、
  page 矩形 <0.5%、符号 CW+、0° 行对齐边回 nil（模型特性，非 bug）。
- 真实 RAW 抽检未执行：input/RAW 现有 DSC00012.ARW / DSC09991.ARW
  （建筑/风景，含疑似斜地平线与建筑立面）+ DSC00012.jpg 可作对照。
- 人工步骤（解锁后）：打开上述 RAW → ashift 面板点「自动水平」→ 确认
  rotation 回填合理值且 history +1；有建筑立面时点「自动检测」→ 确认
  透视参数收敛且无病态恒等回退；失败 toast 时确认参数不动。
- 状态：pending-manual（headless 无人值守，合成探针为验收依据）。
