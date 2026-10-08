# 全史瘦身手术规格（第二次）— M3 收官后自动执行

> 触发条件：**M3 VALIDATION 落签后**、无在飞 worker 时执行（排程：GOAL-STATE 队列，2026-10-08 用户令「加入流水线，M3 收官后自动做」）。
> 上一次同类手术：L070（2026-10-08，pack 1.91GiB→907MB）。

## 目标
剥离「不在当前 tip 上」的历史大对象：①Resources/LUTs 旧再生成版本（pack 内 314MB）②已归档证据的历史版本（gui-acceptance 旧轮 + GOAL-STATE 旧版本等）——**源码路径的历史 blob 一律不动**（明细史考古价值）。

## 步骤
1. 前置断言：`git log --format='%B' main | perl -CSD -ne 'exit 1 if /[\x{4e00}-\x{9fff}]/'`（零中文基线保持）；`git status` 无在飞 worker 产物；release 分支未检出（独立 worktree 无碍）
2. 计算 strip 集：
   ```
   git rev-list --objects main | ... # tip 可达 blob 集 A（保留）
   git cat-file --batch-check --batch-all-objects   # 全量 blob 集 B
   strip = B - A，且仅保留满足：路径前缀 ∈ {.work/gui-acceptance/, .work/gsd/, Resources/LUTs/} 或 size > 1M
   ```
   写 ids 文件后：`git filter-repo --force --strip-blobs-with-ids <ids>`
3. 收尾：`git reflog expire --expire=now --all && git gc --prune=now`；重查 size-pack（预期 907MB → ~400-500MB）
4. **re-add 被 filter-repo 清掉的 remotes**（origin ADO + github——L070 家族坑）+ `git branch --set-upstream-to=github/main release`
5. `git push --force origin main`；github 不需要推（release 谱系不变，若 SHA 变化则按 release-sync 流程重推 tip 主题提交）
6. 记账：GOAL-STATE 续接点 + LESSONS 增行 + sha-rewrite-map 若有 SHA 变化则增补

## 红线
- 源码/Tests/Scripts 路径历史 blob 不剥离；message 不动（本次纯 blob 手术）；push 收敛主会话
