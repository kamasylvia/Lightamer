# C 路 omp 全量深读——CREDENTIAL-BLOCKED（2026-10-19 08:10）

- 首派（直连）：403 RegionError「not available in your country」→ px --up 代理链建立（10809）
- 重派（代理注入）：**401 api_key_expired**——OpenCode API key 过期，Console 新建 key 才能续（重登不续期）
- 结论：非 429 额度问题，是凭证过期，重试无意义。任务书保留（omp-task.md），proxy daemon 保持运行待重试
- 解锁条件：用户新建 OpenCode API key 并替换后，重跑 `nohup omp -p --auto-approve --thinking max "$(cat .work/audits/xcode27-skills-2026-10/omp-task.md)" > omp-stdout.log 2>&1 &`（带 10809 代理 env）
- A/B 路产物不受影响（LANEA/LANEB 已在库）
