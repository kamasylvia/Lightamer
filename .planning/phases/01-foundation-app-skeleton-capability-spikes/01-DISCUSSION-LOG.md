# Phase 1: Foundation, App Skeleton & Capability Spikes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-03 (initial), 2026-08-04 (revision)
**Phase:** 1-Foundation, App Skeleton & Capability Spikes
**Areas discussed:** Xcode 工程搭建, App 窗口布局, MetalContext 设计, CIRAW 解码封装, Spike 交付形式, 错误处理与用户提示, 测试与 CI 策略, 性能预算与插桩, Swift Concurrency 模型, **解耦架构修订（多 target + Tuist）**

---

## 解耦架构修订（2026-08-04）

### 触发
用户提出："如今的规划足够解耦吗？未来可能的改动会很多，因此希望项目尽量解耦。"

### 分析
识别出 5 处真实耦合风险：(1) 单 app target 无编译器强制的边界（最大缺口）；(2) Capture One 图层模型没在 Phase 1/2 抽象（延迟耦合，L005 警告）；(3) EditorState 有 god-object 风险；(4) 没有子系统 public API 表面定义；(5) RAWDecoder 是 class 不是 protocol（one-way）。

### 工具选型（Tuist vs XcodeGen vs SPM）
| Option | Description | Selected |
|--------|-------------|----------|
| 多 target + Tuist | Project.swift 类型安全、依赖图、缓存；多 target 运维优势 | ✓ |
| 多 target + XcodeGen | YAML 配置冗长，不如 Tuist 干净 | |
| 本地 SPM package | 最纯粹，但无依赖图可视化；agent 推荐，用户选 Tuist | |

**User's choice:** 多 target + Tuist。理由：未来 target 数量可能增长（iop 按类别拆、Session/Export 独立），Tuist 的依赖图与缓存红利显现；Project.swift 类型安全比 YAML 干净。
**Notes:** 三条路在"解耦强度"上完全相同（都靠 Swift module 边界）。差异在多 target 配置运维。用户明确选 Tuist。

### 修订的决策
- **D-02 REVISED**: 单 app target → 多 target + Tuist（one-way）
- **D-03 REVISED**: 子系统目录 → 多 target module 布局（LightamerCore / LightamerIOP / app / Tests / UITests，每个独立 Swift module，internal 限定模块内、public 暴露 API 表面）
- **D-03a NEW**: Layer 抽象骨架在 Phase 1 定义（LightamerCore 内 protocol Layer / struct LayerStack），Phase 2 pixelpipe layer-aware，Phase 6 填实现（L005 对策）
- **D-03b NEW**: 状态隔离契约（SessionState / EditorState / ExportState / InspectorState 独立 @Observable 对象，禁止 god-object）
- **D-03c NEW**: 子系统 API 契约文档（每个 module 目录 API.md，列 public 表面 vs internal）

**影响**: Phase 1 的 6 个 PLAN.md 需要修订以匹配新 module 结构（Plan 01 的 project.yml → Project.swift + 多 target；Plan 02-04 的文件路径调整到 LightamerCore/LightamerIOP；新增 Layer 骨架任务；状态对象按 D-03b 隔离）。

---

---

## Xcode 工程搭建

### 工程工具
| Option | Description | Selected |
|--------|-------------|----------|
| XcodeGen | project.yml 生成 .xcodeproj，不提交 .pbxproj，开源主流 | ✓ |
| 手写 .xcodeproj | 原生无额外工具，但多人 merge 冲突 | |
| Tuist | 更现代但单 target 下红利用不上 | |

**User's choice:** 先问"Tuist 更现代？体现在哪里？"，深入对比后选 XcodeGen（先单 target 后迁移路线）。
**Notes:** 用户质疑"这是巨型项目，Tuist 没优势吗"。澄清：Tuist 红利（依赖图缓存/选择性生成/二进制缓存）依赖多 target 边界；单 app target 下用不上。用户最终选"先单 target 后迁移"——务实路线，避免前期多 target 配置复杂度。

### 模块组织
| Option | Description | Selected |
|--------|-------------|----------|
| 子系统目录 | Sources/Core, Sources/IOP, Sources/UI... 同一 app target | ✓ |
| 多 SPM 包 | 每子系统独立 package，隔离强但配置复杂 | |
| 扁平结构 | 全放一目录后期再拆 | |

### 资源位置
| Option | Description | Selected |
|--------|-------------|----------|
| Resources/ 目录 | .metallib、String Catalog、golden image 随 app target 打包 | ✓ |
| shader 源随 target | .metal 直接编译，调试重编慢 | |

### Bundle ID
| Option | Description | Selected |
|--------|-------------|----------|
| com.kamasylvia.lightamer | 与 azure devops 组织 + github 一致 | ✓ |
| app.lightamer | 更短但不符合反向域名 | |

---

## App 窗口布局

### 主窗口结构
| Option | Description | Selected |
|--------|-------------|----------|
| 三栏 NavigationSplitView | 左导航/中网格编辑/右 Inspector，与 C1/LR/DT 一致 | ✓ |
| 两栏 | 导航+主区，iop 面板需折叠 | |
| 单窗全屏 | 沉浸但导航不便 | |

**User's choice:** 三栏，但布局可调节（C1 做法）。

### 三栏可调节范围
| Option | Description | Selected |
|--------|-------------|----------|
| 拖动调宽 | NavigationSplitView 原生支持 | ✓ |
| 折叠/隐藏面板 | C1 风格 Tab 隐藏 | ✓ |
| 布局位置记忆 | 下次打开恢复 | ✓ |
| 上下左右栏可互换 | C1 高级特性 | ✓（后期补） |

### 网格/编辑关系
| Option | Description | Selected |
|--------|-------------|----------|
| 同窗切换 | 点缩略图进编辑，C1 风格 | ✓ |
| 独立编辑窗口 | 双击开新窗口，可同时看多张 | |

### 深色模式
| Option | Description | Selected |
|--------|-------------|----------|
| v1 强制深色 | 专业后期默认深色背景，色彩判断准 | ✓ |
| 跟随系统 | 用户友好但浅色下判断不准 | |
| 可切换 | 默认深色但可手动切 | |

**Notes:** 用户明确 v1 强制深色，v2 加入可切换 + 跟随系统。

### 首次启动
| Option | Description | Selected |
|--------|-------------|----------|
| 空状态提示 | "选择文件夹创建 Session"/"拖放 RAW"，无向导无示例 | ✓ |
| 启动向导 | 欢迎→选文件夹→示例 | |
| 示例 Session | 内置示例 RAW 即开即用 | |

### 顶部工具栏
| Option | Description | Selected |
|--------|-------------|----------|
| 顶部工具栏 + 菜单栏 | 导入/导出/前后对比/缩放高频入口 | ✓ |
| 无工具栏 | 全走菜单/右键 | |
| Phase 1 不做 | 只留菜单栏 | |

### Phase 1 编辑视图范围
| Option | Description | Selected |
|--------|-------------|----------|
| 只显示解码后 RAW | 无调整无缩放交互，验证 MTKView 桥接 | ✓ |
| 含缩放交互 | 双指缩放/拖动平移 | |

---

## MetalContext 设计

### Device 选择
| Option | Description | Selected |
|--------|-------------|----------|
| 系统默认 device | MTLCreateSystemDefaultDevice()，Apple Silicon 统一内存 | ✓ |
| 多 GPU 选择 | MTLCopyAllDevices()，Mac Pro/eGPU 场景 | |
| 用户可选 GPU | 过度设计 | |

### CommandQueue 策略
| Option | Description | Selected |
|--------|-------------|----------|
| 单 CommandQueue | Phase 1 无争抢，后期导出再加队列 | ✓ |
| 渲染+计算双队列 | 隔离优先级但同步复杂 | |
| 三队列（含导出） | 过度设计 | |

**User's choice:** 先问"单队列影响性能吗"。澄清：Metal 并行单位是 command buffer 非 queue；Phase 1 只显示无交互无争抢；Darktable 也单 queue 起步。用户确认单队列。

### PSO 缓存策略
| Option | Description | Selected |
|--------|-------------|----------|
| 懒加载+内存缓存 | 活跃 PSO 占用小，Metal 不支持 PSO 磁盘序列化 | ✓ |
| 启动预编译 | 冷启动慢但首次无卡顿 | |
| 懒加载+磁盘缓存 | Metal 序列化 PSO 支持有限 | |

**User's choice:** 先问"机器内存紧张（16G），SSD 紧张，外置丰余，怎么选？"。澄清：PSO 内存占用几十 MB（非 GB 级）；16GB 瓶颈是图像数据（100MP=1.6GB/张）非 PSO；Metal 不支持完整 PSO 磁盘序列化。用户确认懒加载+内存缓存。

### function-constants
| Option | Description | Selected |
|--------|-------------|----------|
| 用 function-constants | 编译时参数注入，多特化变体 | ✓ |
| 不用，运行时参数 | 简单但失优化 | |

### dispatch API 形态
| Option | Description | Selected |
|--------|-------------|----------|
| 两层 API | 高层 dispatch2D + 底层 encoder | ✓ |
| 高层 dispatch2D | 简单起步 | |
| 暴露底层 encoder | 灵活但重复代码 | |

### 错误处理
| Option | Description | Selected |
|--------|-------------|----------|
| Swift throws | typed error，调用层 catch | ✓ |
| Result 类型 | 显式但调用点冗长 | |
| fatalError | 开发期硬崩，生产不安全 | |

### tiling 框架
| Option | Description | Selected |
|--------|-------------|----------|
| Phase 1 不做 | 100MP 统一内存容得下，Phase 2 再加 | ✓ |
| Phase 1 就做 | 框架就绪但增骨架复杂度 | |

**Notes:** 用户先选"Phase 1 就做"，追问范围后改为"重新评估不做"（Phase 2 再做）。

---

## CIRAW 解码封装

### 封装形态
| Option | Description | Selected |
|--------|-------------|----------|
| RAWDecoder 封装类 | 隐藏 CIRAWFilter，为 pixelpipe 提供 clean 输入 | ✓ |
| 直接暴露 CIRAWFilter | 简单但散乱 | |
| 协议+多实现 | 过度设计（不引 libraw） | |

### RAW 9 opt-in 策略
| Option | Description | Selected |
|--------|-------------|----------|
| 默认 RAW 9+降级 | 用户无感获最佳质量 | ✓ |
| 用户可选 | 可控但多一步 | |
| 只用 RAW 8 | 保守，beta 期不用 9 | |

### 元数据接口
| Option | Description | Selected |
|--------|-------------|----------|
| 拍摄元数据 | EXIF/IPTC/XMP（相机/镜头/焦距等） | ✓ |
| RAW 技术参数 | 黑/白电平/基准曝光/中性色度（Phase 2 色彩管理用） | ✓ |
| 嵌入 segmentation matte | iPhone ProRAW 嵌入（Phase 7 AI 用） | ✓ |

### 非 RAW 输入
| Option | Description | Selected |
|--------|-------------|----------|
| 统一入口 | RAWDecoder 内部判断走 CIRAW/CGImageSource | ✓ |
| RAW/非RAW 分开 | 职责清晰但调用方需选 | |

---

## Spike 交付形式

### 组合方式
| Option | Description | Selected |
|--------|-------------|----------|
| 两个独立 spike | CIRAW 9 边界 + 100MP 性能分开 | ✓ |
| 合并一个 | 交织但混合关注点 | |
| 只做 CIRAW 9 | 100MP 等 Phase 2 | |

### 交付物
| Option | Description | Selected |
|--------|-------------|----------|
| 报告文档 | .planning/spikes/ 下，能力表+性能数据+结论 | ✓ |
| golden image 样本 | 不同相机/传感器解码参考图 | ✓ |
| 验证用 app 代码 | 独立分支，验证后提炼或弃 | ✓ |

---

## 错误处理与用户提示

### 错误传递架构
| Option | Description | Selected |
|--------|-------------|----------|
| 统一 AppError 枚举 | typed error，UI 统一转人可读 | ✓ |
| 分领域 Error 类型 | 细粒度但重复 | |
| Result 返回值 | 显式但冗长 | |

### 用户提示
| Option | Description | Selected |
|--------|-------------|----------|
| 分级提示 | 非阻塞 alert/阻塞 alert/toast | ✓ |
| 全走模态 alert | 简单但打断流程 | |
| Phase 1 只 log | 后期再补 UI | |

### 错误日志
| Option | Description | Selected |
|--------|-------------|----------|
| os.Logger | Apple 统一日志，Console.app 可查 | ✓ |
| 自写日志层 | 可控但多维护 | |
| 先 print 后期换 | 短期但技术债 | |

---

## 测试与 CI 策略

### Phase 1 测试范围
| Option | Description | Selected |
|--------|-------------|----------|
| 骨架+示例单测 | test target 就绪，不追求覆盖率 | ✓ |
| 完整测试 | 单测+集成+golden-image 框架 | |
| Phase 1 不做 | Phase 2 再搭 | |

### 测试 target 结构
| Option | Description | Selected |
|--------|-------------|----------|
| Tests + UITests target | macOS app 标准结构 | ✓ |
| 只单测 target | UI 测后期补 | |
| 测试同 target | 调试快但生产含测试代码 | |

### CI
| Option | Description | Selected |
|--------|-------------|----------|
| 后期再接 CI | 减少前期配置负担 | ✓ |
| Phase 1 就接 | 早期建质量门 | |

---

## 性能预算与插桩

### 度量指标
| Option | Description | Selected |
|--------|-------------|----------|
| 60fps 帧率 | Core Value 指标 | ✓ |
| 解码耗时 | 文件到显示的时间 | ✓ |
| 内存占用 | 峰值/稳态，16GB 硬约束 | ✓ |
| kernel GPU 耗时 | 每个 iop 的 GPU 时间 | ✓ |

### 插桩工具
| Option | Description | Selected |
|--------|-------------|----------|
| Instruments + os.signpost | Xcode 自带 + 代码插桩组合 | ✓ |
| 自写性能日志 | 可控但重复造轮 | |

### 100MP 预算
| Option | Description | Selected |
|--------|-------------|----------|
| 设硬预算 | 解码≤2s/显示≤500ms/稳态内存≤4GB | ✓ |
| 只记录不设预算 | 后期根据实测定 | |

---

## Swift Concurrency 模型

### 并发基础
| Option | Description | Selected |
|--------|-------------|----------|
| Swift Concurrency/actor | async/await + MainActor + actor，Swift 6 data race 安全 | ✓ |
| GCD | 传统但 data race 需手动同步 | |
| Combine | 响应式但非主流 | |

### 解码后台执行
| Option | Description | Selected |
|--------|-------------|----------|
| 后台 async + 可取消 | 不阻塞 UI，用户可取消 | ✓ |
| 主线程同步 | 简单但大图卡 UI | |
| 预解码队列 | 优化但复杂，Phase 1 过度 | |

### 状态管理
| Option | Description | Selected |
|--------|-------------|----------|
| @Observable macro | 性能好，与 async/await 兼容 | ✓ |
| ObservableObject | 熟但落后 | |
| Store 模式 | 过度设计 | |

---

## the agent's Discretion

无——所有 area 用户均做了具体选择，无"你决定"项。

## Deferred Ideas

- 上下左右栏互换（C1 完全可重构布局）——后期补
- tiling 框架——Phase 2
- CI 接入——发布前
- 深色模式可切换/跟随系统——v2
- 预热高频 kernel PSO——若冷启动延迟感知明显再加
- 多 GPU/用户可选 GPU——不做
