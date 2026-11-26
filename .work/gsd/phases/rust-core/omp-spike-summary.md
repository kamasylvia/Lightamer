# omp SPIKE-RUST-APPLE 摘要（2026-11-25）

结论：非 UI 用 Rust、UI 用 AppKit，四项 Apple 能力保得住。Rust 可直接驱动 CIRAW / ImageIO / ColorSync / Vision；UI 层原生 Swift 足够。限定：Metal 着色器是 Apple 专属资产，跨平台需第二实现；四项能力仍把核心钉在 macOS，需 trait + 第二实现才可移植。

- S4 Metal：仓库原样 2 个 .metal，Rust 运行时编译派发，与 Swift 参照逐字节相同（sha256 b0e01d2f…）。
- S1 CIRAW：9504×6336 RGBA16Float，解码器 [7,8,9]，直接路径中位 945.7 ms（含 481MB 回读）；rawspeed→122MB 内存 DNG→CIRAW 中位 398.6 ms。
- S3 ImageIO/ColorSync：JPEG/HEIC/AVIF 全成；sRGB 以 nclx 标记、不写 ICC payload，非标准 ROMM ICC 补测确写 JPEG APP2/HEIC prof；ColorSync sRGB→P3 输出与 Swift 逐字节相同（sha256 88cffad7…）。
- S2 Vision：完成回调经 mpsc 回主线程；CC0 样张 9/9 无人脸，人脸 0/0，矩形非空对照 1 框逐字符一致。
- S5 UniFFI：同步/async/事件回调全通；MTLTexture 以 u64 过桥、无图像序列化，Rust 写首行/Swift 读回 [12,200,77,255]（replaceRegion/getBytes 各一次 API 拷贝，非字面零拷贝）。
- 未验证：人脸非空、Vision landmarks/horizon/分割、AVIF 10-bit/HDR 与自定义 ICC、ColorSync 其它布局、CIRAW v9/其它相机、75 个 shader 全量、跨平台、swift-bridge、rawspeed 色彩标定与 LGPL 法务。
- 复审：独立 omp 实例 PASS / 3 error + 10 minor，已按 findings 修订（报告 §6）。
- 交付：仓内 .work/gsd/phases/rust-core/ 下报告 + 源码 + 证据；仓外工作区 out/ 保留可执行与对比产物；target/（2.2GB）已删。
