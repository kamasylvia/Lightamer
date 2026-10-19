# Lightamer Xcode 27 官方 skills 对照审计——C 路（omp 全量深读）

## 角色与目标
你是独立第三路审计员。对 `/Volumes/UNITEK/Documents/Development/Lightamer` 的 App 层 SwiftUI 视图代码做**判断级全量深读审计**，对照 Xcode 27 官方 agent skills 的最佳实践标准。**纯只读**：禁止改任何源码/测试/构建文件，禁止跑构建或测试，只允许写 `.work/audits/xcode27-skills-2026-10/` 下的产物。

## 输入集合
1. **审计对象**：`App/Sources/` 下所有 `import SwiftUI` 的文件（共 **114 个**，`grep -rl "import SwiftUI" App/Sources --include="*.swift"` 口径），逐文件深读。
2. **判断标准**（先读后审）：
   - `.work/xcode27-skills/swiftui-specialist/references/`：structure.md / dataflow.md / environment.md / foreach.md / animations.md / localization.md / modifiers.md / soft-deprecation.md
   - `.work/xcode27-skills/swiftui-whats-new-27/references/`：state-macro.md / content-builder.md

## 变换规则（七维审查，逐文件过）
1. **view 拆分度**：巨型 body、深嵌套 ViewBuilder、可抽取的子 View struct（structure.md 标准）
2. **数据流**：@State/@Binding/@Observable 使用形态、computed 重复计算该缓存、环境注入链（dataflow.md/environment.md）
3. **ForEach identity**：id 稳定性、位置≠身份、行漂移风险（foreach.md）
4. **动画**：隐式动画滥用、withAnimation 缺失（animations.md）
5. **本地化**：插值参数顺序、复数规则缺失、词序硬拼（localization.md）
6. **@State macro 陷阱**（state-macro.md）：「重排 init 赋值是错的」类 SDK 27 陷阱形态
7. **ViewBuilder 类型检查热点**（content-builder.md）：超时风险形态、歧义重载

**finding 格式**：`severity(error/major/minor/obs)` + `file:line`（可定位）+ skill 出处（文件+节）+ 修复草图一句。

## 房内约定优先（与 skill 泛则冲突时，约定赢，冲突处记 obs 并引用约定条目）
- KD-4 注入式 defaults（body 零 UserDefaults 直读）
- app-root sheet 闭包禁裸 `@Environment`（内容面重注入/init 参数注入二选一）
- `String.LocalizationValue("prefix_\(x)")` 插值形态禁止（动态查表键走显式 switch）
- xcstrings 尾块纯插入纪律
- disable-not-unmount 三纪律（agent 控制期禁编辑面）
- D-H1 提交语义（begin/end 配对）
- 2026-10-19 起壳交接（NSApplicationDelegate + NSHostingView）为既定方向——「SwiftUI App lifecycle 层」的观察照记但不作为迁移阻断项

## 输出契约（两件，缺一不可）
1. **落盘正本**：`.work/audits/xcode27-skills-2026-10/OMP-FINDINGS.md`——结构：结论头 `PASS / N error + N major + N minor + N obs` + 覆盖面声明（实际深读的文件数/清单口径）+ 逐 finding 分级清单 + 方法注记。
2. **stdout 最终消息**：把全部审计结论**合并为最后一条消息一次性完整输出**（不拆多条）。

## 验收清单（自检后再交卷）
- [ ] 114 个 SwiftUI 文件全覆盖（报告里给实读计数）
- [ ] 每个 finding 带 file:line 可定位
- [ ] 结论头格式正确
- [ ] OMP-FINDINGS.md 已落盘
- [ ] 零源码/测试/构建文件改动

## 边界
- 不需要跑任何构建/测试/git 写操作；你的全部产出 = 那一个 md 文件 + stdout。
- 遇到需要运行才能验证的问题（行为级），降级记 obs 标「需运行时验证」，不要自己起 GUI。
