# AGENTS.md

本文件为在本仓库工作的 AI 代理（以及人类贡献者）提供导航与约定速查。
权威仍是上游 [CONTRIBUTING.md](CONTRIBUTING.md)、[dev-doc/](dev-doc/) 与项目 wiki，本文件仅做浓缩与本地化补充。

---

## 仓库定位

darktable 是开源的 RAW 摄影“数字暗房”：lighttable（图库管理）+ darkroom（pixelpipe 非破坏性编辑）。
本 fork（`kamasylvia/darktable-auto-rating`）在此之上叠加了 **AI 自动评分**功能，相关约定见下方“Fork 专属”。

## 远程与分支

| Remote | 位置 | 用途 |
|---|---|---|
| `origin` | ADO · *Forked from GitHub* | 主开发远程 |
| `kamasylvia` | ADO · *Kamasylvia* | 镜像远程 |
| `github` | `darktable-org/darktable` | **真正上游**（只读同步源） |
| `github-fork` | `kamasylvia/darktable-auto-rating` | GitHub fork，保留完整 fork 历史 |
| `sourceforge` | `darktable-auto-rating/code` | 备份远程 |

- 默认分支：`master`（与上游一致）。
- 从上游同步：`git fetch github && git reset --hard github/master`；之后若需要保留本仓库的 CI 配置，手工把 `.azure-pipelines/` 加回再提交。
- force-push 仅对 ADO 的 `origin` / `kamasylvia` 允许；**永远不要** force-push 到 `github`。

## 构建

需要先拉子模块（RawSpeed / LibRaw / libxcf / OpenCL headers / whereami 必需）：

```bash
git submodule update --init
# 一键（推荐）
./build.sh --prefix /opt/darktable --build-type Release --install --sudo
# 或手动
cmake -B build -DCMAKE_INSTALL_PREFIX=/opt/darktable/
cmake --build build && sudo cmake --install build
```

- macOS：见 `packaging/macosx/BUILD_hb.txt`（Homebrew）或 `BUILD.txt`（MacPorts）。
- 关键选项见 `DefineOptions.cmake`（`USE_LIBRAW`、`USE_OPENCL`、`USE_OPENMP`、`USE_AI`、`USE_AVIF/HEIF/JXL/WEBP` …）；`USE_RAWSPEED` 无开关——RawSpeed 是内嵌子模块，始终编译。
- 构建前若曾构建过其他版本，**务必 `rm -Rf build/`**，否则旧缓存常导致诡异 bug。

## 代码地图

### RAW 解码（加载入口）
- `src/imageio/imageio.c` — 总分发。`dt_imageio_open()`（:1626）→ 按魔数表（:274）选 loader；失败链：`rawspeed` → `libraw` → `exotic`(GM/IM)。
- `src/imageio/imageio_rawspeed.cc` — 主 RAW 解码（Canon CR2/CRW、Nikon NEF、Sony ARW、Fuji RAF、Olympus ORF、Panasonic RW2、Phase One IIQ…）。
- `src/imageio/imageio_libraw.c` — 兜底，Canon **CR3**（HEIF 基底）与 Sigma **X3F**。
- 命中哪个 loader 记录在 `img->loader`（`dt_image_loader_t`，`src/common/image.h:198`）。

### Pixelpipe（解码之后）
- `src/iop/rawprepare.c` — 黑电平/白点/传感器裁剪（demosaic 前的第一步）。
- `src/iop/demosaic.c` + `src/iop/demosaicing/` — 去马赛克（PPG/AMAZE/LMMSE/VNG/RCD/Dual 等）。
- `src/iop/temperature.c` — 白平衡（读 decoder 填充的 `img->wb_coeffs`）。
- `src/iop/colorin.c` — 相机→XYZ 色彩矩阵（读 `img->d65_color_matrix`，矩阵由 RawSpeed 填充）。
- `src/iop/highlights.c` + `src/iop/hlreconstruct/` — 高光重建。
- 架构总览：`dev-doc/pixelpipe_architecture.md`。

### imageio 插件接口
- 导入/编码格式插件：`src/imageio/format/`（jpeg/png/tiff/avif/heif/jxl/webp/exr/j2k/pfm/ppm/xcf/pdf/copy）。
- 导出目标插件：`src/imageio/storage/`（disk/gallery/email/piwigo/latex）。
- 接口定义：`src/imageio/format/imageio_format_api.h`、`src/imageio/storage/imageio_storage_api.h`。

### macOS/平台
- `src/osx/osx.{h,mm}` — 仅 UI/打包集成（菜单栏、bundle、URL），用 Carbon/AppKit + gtkosx-application。
- 顶层 `CMakeLists.txt` 中 `APPLE` 条件（:71/116/131/139），`CMAKE_FIND_FRAMEWORK LAST`。
- **当前完全不用 Apple 的 ImageIO/CoreImage/CoreGraphics 做图像解码**——那会是全新增加。

## 编码约定

- 缩进 2 空格（`shiftwidth=2 expandtab tabstop=2`）；格式化以 `src/.clang-format` 为准。
- 命名：函数/类型加 `dt_` 前缀；结构体 `typedef struct dt_*_t`；GLib 风格（`gboolean`、`G_BEGIN_DECLS`）。
- 头文件用 `#pragma once`；每个源文件末尾保留标准 vim/kate modeline（`tools/update_modelines.py` 维护）。
- `src/external/` 是第三方/子模块，**禁用格式化**（其内 `.clang-format` = `DisableFormat: true`），改动应进各自上游。
- 新 IOP 模块看 `dev-doc/New_Module_Guide.md` 与 `IOP_Module_API.md`。

## 代理工作约定（本地补充）

- 每轮对话结束按需更新 `TODO.md` / `AGENTS.md`。
- 提交前确保有对应 GitHub issue；commit message 末尾用 `fixes #NN` / `closes #NN` / `refs #NN` 关联（issues 禁用时跳过并说明）。
- 探索性调研优先用子代理 fan-out；写代码前先读周边文件、对齐既有风格。
- 破坏性 / 对外操作（force-push、删远程分支、发公开内容）必须先确认。
