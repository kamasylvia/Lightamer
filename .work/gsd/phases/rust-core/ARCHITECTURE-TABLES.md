# ARCHITECTURE-TABLES — 会话架构定稿调研长表（正文见 ARCHITECTURE.md）

> 口径：Capture One 官方支持文档经 web.archive.org 2025 年快照取（support.captureone.com 本体被 Cloudflare 挡，curl 直取只拿到挑战页，已如实记录）；官方博客 sessions-101/102/103 经官网与 web.archive.org 取。LightCraft 本地树 `/Volumes/UNITEK/Documents/Development/lightcraft`，HEAD `0da998f2`（与 FRAMEWORK.md 同锚）。行数命令：`sed -n` / `grep -n` 当日重跑。
> 每条官方说法带链接与原文引用；官方没写的标「官方未说明」；无实测的判断标「推断」。

---

## T-A1 Capture One 会话模型证据表（Q1 全量引文）

凡链接为 `https://support.captureone.com/hc/en-us/articles/<id>`（取文经 2025 年 web.archive.org 快照；博客为 captureone.com / learn.captureone.com 经官网或 2025-01 快照）。

| # | 主题 | 官方说法（原文引用） | 出处 |
|---|---|---|---|
| 1 | 会话定义 | "A Session is a self-contained project format in Capture One. It stores RAW files, adjustment settings, previews, and metadata in a single folder structure, making it easy to organize and transfer." | Sessions 指南 `360003115137`（2025-04-24 更新） |
| 2 | 适用场景 | "Sessions are especially useful for tethered shooting and short-term projects." 另：`Why Use Sessions?` 列 "Fast access to files via favorite folders / Local image settings and cache / Simple portability / Flexibility for using your existing folder structure without importing" | 同上 |
| 3 | 四个子文件夹 | "Rename or place Session folders (Capture, Selects, Output, Trash)."（新建会话对话框步骤） | 同上 `How to Create a New Session` |
| 4 | 文件夹可改名可移位 | 同上句 "Rename or place Session folders"；另 102："Right click on the Capture folder in the system view and choose 'new inside'."（可在 Capture 内建拍摄子文件夹） | 同上；博客 102 |
| 5 | 数据库文件名 | "File > Open and navigate to the .cosessiondb file"；"Double-click the .cosessiondb file" | 同上 `Opening a Session` |
| 6 | 数据库里有收藏与相册 | "Session Favorites and Albums are stored in the .cosessiondb file" | 同上 `Additional Information` |
| 7 | 调整不在数据库里 | "Providing the CaptureOne sub-folder (containing the adjustment files) remains within the source images' folder, it can be moved to any location and viewed on any local computer running Capture One."（即：不要会话数据库文件也行） | 同上 `Working with Sessions in a Daily Workflow` |
| 8 | 调整存在图片旁的子文件夹 | "Settings are stored locally in a CaptureOne subfolder, enabling easy transport and reuse." | 同上 |
| 9 | 调整文件版本化子文件夹名 | "The Settings165 subfolder in each image folder (it contains all the image adjustments are kept)."（备份清单；`Settings165` 对应 v16.5，命名规则=版本号，属推断） | 备份指南 `27502751010333`（2025-11-23 更新）`What to back up in a session` |
| 10 | 调整文件后缀 .cos | "Outside of the XMP sidecar workflow, the metadata adjustments are recorded along with the rest of the adjustments in .cos files (when in a Session) or in the database (when in a Catalog) separately for each source image." | XMP 指南 `360002544898`（2025-03-16 更新） |
| 11 | 不导入直接浏览 | "You don't even have to import images using a Session, you can continue to use your existing folder structure."；FAQ："Do Sessions require importing files? No, you can browse your existing file system directly." | Sessions 指南 + FAQ |
| 12 | 浏览即建缓存与设置 | "A simple click on a folder of RAW files in the library is enough to trigger generation of cache. Settings and images will start to load immediately. Once created, these are used again next time you revisit the folder." | 博客 101（官网直取；页顶注 "discusses an outdated version"） |
| 13 | 无数据库可看图 | "As long as you have a folder of images with the settings, you can view this on any machine – even without the accompanying session database." | 博客 101 |
| 14 | Capture 用途（联机+导入默认） | 101："Captures (destination folder for tethered)"；导入指南："From the Destination fly-out menu, select the Capture Folder. This option is the standard folder to import files when using Sessions." | 博客 101；导入指南 `360002521938` |
| 15 | Output 用途（处理落点） | 101："Output (assigned as the destination for all processing)"；102："I need to do the same for the processed folder (where all the conversions are kept). So, again I go to the folder browser and find my folder – right click, set as output. Now, when I process images, they go there." | 博客 101、102 |
| 16 | Output 可排除在浏览外 | 塔台称指南写过；本次所取 2025-04 版指南正文无此句。**版本差异，标查不到。** | 查不到（见 T-A9 #1） |
| 17 | Selects 是物理移动 | "Once an image is selected, press on the Move to Selects icon on the toolbar and the location of the file will change to the Selects Folder."；"The Selects Folder (previously known as the Move-To folder) is automatically created when a new session is started. It is designed to enable users to quickly and easily move image files." | Selects 指南 `360002524157`（2025-03-16 更新） |
| 18 | Selects 快捷键 | "right-click on a thumbnail in the browser and select Move to Selects Folder. Alternatively, use the keyboard shortcut Cmd+J/ Ctrl+J (macOS/Windows)." | 同上 |
| 19 | 不想物理移动用相册 | "When you don't want to physically move the images, then create an Album or an Album within a Project or Group and nominate it as a Selects Collection instead." | 同上 `Selects Collection` |
| 20 | 删除=移进 Trash | "You can delete an image by selecting it in the Browser and going to Image > Delete (Move to Catalog/Session Trash) or Delete from Disk"；"The former option moves the source image to a trash folder, where it can be reviewed and then permanently deleted thereafter." | 删除总述 `360002546757`（2025-03-16 更新） |
| 21 | 清空 Trash 不可撤回 | "When images and their variants are located inside the Session Trash, emptying the Trash will permanently delete your source images."；"Deleting images from the Session Trash cannot be undone, images are not placed in the system trash and cannot be retrieved later as a result." | Session Trash 指南 `360002546518` |
| 22 | Trash 内只读 | "Images inside the Trash are read-only and cannot be edited (thumbnails are indicated by a small crossed-over pencil icon, while all the sliders and tools are disabled)." | 同上 |
| 23 | 撤回删除=拖回 | "If you realize that you have made a mistake before deleting, press Cancel, select the image from the Browser and drag the image and its variants back to the relevant Session or System Folder in the Library." | 同上 |
| 24 | 清空入口 | "Choose File -> Empty Session Trash. Focus (i.e., pre-selection) on the Trash Collection is not required. You can also delete images and their variants individually from the Trash." | 同上 |
| 25 | 收藏的三种作用 | 102："One: it makes a small heart on the folder in the library… a shortcut to the actual folder… You can also set Favorites as Capture/Selects/Output/Trash like it's the actual folder"；"Two: it indexes the content of that folder in the session database file, making it faster to load and opens up the contents for search."；"Three: Folders marked as favorites (and their relative position to the session) are remembered when making custom templates." | 博客 102（2025-01 快照） |
| 26 | 智能相册跨收藏搜索 | "You specify rules for it, and if it finds images in the favorites that match, it will show it in the Smart Album."；"As smart albums work across all Favorite folders, this quickly gives you an overview of keepers from all shot folders." | 博客 102、103 |
| 27 | 相册是虚拟引用 | "They are in effect 'virtual' folders – meaning they can hold and show you an image but it's just a reference to the actual file which is somewhere else." | 博客 102 |
| 28 | 模板存结构不存图 | "Templates save time by storing Album and Favorite structures for reuse."；"Templates don't store actual images, only folder and album structure"；102："A custom template primarily remembers 3 things in the template. Folders which were favorited, albums/smart albums, and the Next Capture naming set up." | Sessions 指南；博客 102 |
| 29 | 模板制作流程 | "Open a Session and configure the Albums/Favorites. Go to File > Save As Template. Name and save the template. When creating a new Session, select the template from the drop-down menu." | Sessions 指南 `Session Templates` |
| 30 | 同时开多个会话 | "Enable Open in new window in Preferences > General. Open additional Sessions via File > Open Session. Drag and drop files between Sessions as needed."；FAQ："Can I use multiple Sessions at once? Yes. Enable 'Open in new window' in Preferences." | Sessions 指南 `Managing Multiple Sessions at Once` + FAQ |
| 31 | 同一会话开两次 | **官方未说明**（无锁/单写者说明；见 T-A9 #2）。 | 查不到 |
| 32 | 最近会话 10 个 | "File > Open Recent to access up to 10 previous sessions" | Sessions 指南 `Opening a Session` |
| 33 | 搬会话 | "Ensure folder links are Relative to session. Close the Session. Use Finder/Explorer to move the Session folder to the new location."；FAQ："Can I move a Session between computers? Yes, as long as the CaptureOne folder and images are kept in the same relative structure." | Sessions 指南 `Moving and Relocating Sessions` + FAQ |
| 34 | 删会话=删文件夹 | "Delete the Session folder using your OS."；"Note: Deleting a Session also deletes original files unless backed up." | 同上 `Deleting a Session` |
| 35 | 会话无自动备份 | "Unlike Catalogs, Sessions do not have a built-in backup mechanism."；"Are sessions backed up automatically? No. You must manually back up session folders using third-party tools or OS-level backup utilities." | 备份指南 `Session Backups` + FAQ |
| 36 | 会话备份清单 | "back up the entire session folder, which includes: The .cosessiondb file. Capture, Selects, Output folders. The Settings165 subfolder in each image folder… You may leave out Trash folder and Cache folder if it appears inside any of the session folders." | 备份指南 `What to back up in a session` |
| 37 | 升级只动数据库 | "When opening a Session from an earlier major version of Capture One, you'll be prompted to upgrade the database. Your image adjustments won't change — only the session database is updated."；"Your image variants remain unchanged." | Sessions 指南 `Upgrading Sessions` |
| 38 | 升级自动备份 | "Capture One also creates a backup of the Session database when upgrading to a newer version… Locate the .cosessiondb.backup file within your Session folder. Rename the file by removing the .backup extension." | 备份指南 `Session upgrade backups` |
| 39 | 校验修复 | "Although a Session does not have the same extensive database of a Catalog, it still makes sense to run diagnostic checks occasionally… Go to File > Verify Catalog or Session. Select the .cosessiondb file." | Sessions 指南 `Verifying and Repairing Sessions` |
| 40 | 变体定义 | "Variants are used by Capture One to display the original… source files and to store the adjustments you have made."；"When you adjust an image, the instructions are written to a small BLOB of data called settings."；"what you are looking at on-screen is always a virtual representation of what the final file will look like" | 变体指南 `360002478437`（2025-03-16 更新） |
| 41 | 变体可多份可跨处 | "they can be copied as many times as you like and can even exist in more than one place (in the form of albums). All of these virtual copies can exist as a representation of just one original source image." | 同上 |
| 42 | 目录存调整在库里 | "Each Catalog is a database that contains references to your original image files and stores adjustments, metadata, and user-created collections." | 目录指南 `360003108698`（2025-09-09 更新） |
| 43 | 目录两类工作流 | "Managed workflow: Image files are physically stored inside the Catalog… Referenced workflow: Images are stored outside the Catalog and simply referenced in place." | 同上 |
| 44 | 目录何用 | "You need to manage and search through a large volume of images across multiple shoots. You want advanced organization tools like Projects, Albums, Smart Albums, and Groups. You prefer a centralized database with a flexible file structure and a searchable archive." | 同上 `Catalogs vs. Sessions` |
| 45 | 会话何用 | "You're working on a one-off shoot or a short-term project. You shoot tethered and need quick access to captures, selects, and outputs in dedicated folders. You want to keep everything in a simple, self-contained folder hierarchy." | 同上 |
| 46 | 会话可并入目录 | "You can always import a Session into a Catalog later if you decide to consolidate your workflow."；"When you import a Session, Capture One brings in adjustments, metadata, and collections. Session Folders (Capture, Selects, Output, Trash) are added as Albums, and any folder marked as a Favorite is also included." | 同上；目录指南导入节 |
| 47 | 导入只用于外部介质 | "the Import dialog is used solely for importing from external media such as memory cards, external disks, and a connected camera when that is not being used for tethered capture." | 导入指南 `360002521938`（2025-03-16 更新） |
| 48 | 本地盘用导入会复制出重份 | "It is not recommended to use the importer to access images on a local or external drive like a Catalog. Doing so will copy the images and you will just end up having duplicates of them." | 同上 |
| 49 | 导入默认落 Capture | "From the Destination fly-out menu, select the Capture Folder. This option is the standard folder to import files when using Sessions. It maintains the standard Sessions structure of Capture, Selects, Output, and Trash subfolders." | 同上 |
| 50 | EIP 打包调整 | "If you are a retoucher importing a set of EIP files… remember to add a check-mark to Include Existing Adjustments. Otherwise, none of the accompanying files (adjustments, variants, ICC and LCC profiles, etc.) will be enabled" | 同上 |
| 51 | XMP 只管元数据同步 | "Capture One can read metadata in the following four formats: Embedded EXIF, Embedded IPTC-IIM, Embedded XMP, and .XMP sidecar file."；"Full Sync will update the XMP sidecar files with any metadata changes… It is a two-way synchronization."；"Load will load the information from any XMP sidecar file into the .cos (session) or cocatalogdb (catalog)." | XMP 指南 `360002544898` |
| 52 | RAW 永不改 | "The adjustments made to the image in Capture One are applied to the preview and added to the settings file. No changes are made to the raw data at any time." | RAW 原理 `360002481998`（2025-03-16 更新） |
| 53 | 拖一张图到别文件夹调整是否跟走 | **官方未直接说明。** 间接证据：调整在图片所在文件夹的 `CaptureOne`/`SettingsNNN` 子文件夹内（#7–#9），按相对结构搬运才完整（#33）；103 称用 File > Export Originals 发 RAW+调整（"you can select all from the Green4+ Smart album and file > export (originals) to send the RAWS + adjustments to any location"）。单文件跨文件夹拖拽时设置文件是否自动跟随，官方未说明（社区个案称 Selects 移动曾丢蒙版，属个案非官方）。 | 部分查不到（见 T-A9 #3） |
| 54 | 目录锁/只读 | 目录指南目录列有 "Locking and Unlocking a Read-Only Catalog" 一节（正文未细取；与第 0 期无关）。 | 未细取 |
| 55 | 四文件夹可重指定 | 102："right click, set as output"；"You can also set Favorites as Capture/Selects/Output/Trash like it's the actual folder, without having to find it in system."（四个角色均可重指定到任意收藏文件夹） | 博客 102 |

## T-A2 九月笔记勘误表（逐条对官方核实）

| 笔记说法（出处） | 核实结论 | 依据 |
|---|---|---|
| `Captures/`（FEATURES.md 会话文件夹结构） | **错。以官方为准是 `Capture`**（无 s）。注：2017 年博客 101 写的是 "Captures (destination folder for tethered)"，而 2025 年支持文档统一为 `Capture`。属官方改名或博客笔误，裁决：采用支持文档的 `Capture`。 | T-A1 #3 |
| `Crop/`（ARCHITECTURE.md §5 Session 子系统："Capture/Crop/Output"） | **错。官方四件是 Capture/Selects/Output/Trash，无 Crop。** | T-A1 #3 |
| "Settings/adjustments are stored per-image as sidecar files in the Capture subfolder (.cos for C1)"（FEATURES.md） | **表述不准。** 调整在*每张图所在文件夹*下的 `CaptureOne`/`SettingsNNN` 子文件夹，不是特指 `Capture/` 文件夹；且 `.cos` 后缀见于 XMP 指南。 | T-A1 #8、#9、#10 |
| "<SessionName>.cosessiondb ← cache + tracking DB (NOT the source of truth)"（FEATURES.md） | **半对。** 对调整而言成立（调整真相在设置文件）；但 Favorites/Albums 的真相就在 `.cosessiondb` 里（T-A1 #6），这部分它是真相。 | T-A1 #6、#7 |
| "Each subfolder is assignable: right-click any folder → Set as Capture/Output/Trash folder"（FEATURES.md） | **成立，且 Selects 也可指定**（笔记漏了 Selects）。 | T-A1 #55 |
| Session vs Catalog 对比表（FEATURES.md） | **基本成立**："Source of truth: Filesystem folders + per-image sidecars / Central SQLite DB" 与官方一致（T-A1 #42 会话侧为文件夹+设置文件、目录侧库内含调整）；"Import required: No/Yes" 成立（T-A1 #11、#47）；"Best for" 两行与官方 T-A1 #44、#45 一致。注：官方未明说目录底层是 SQLite（"SQLite" 一词系笔记推断，标推断）。 | T-A1 #11、#42–#47 |
| "Folder workflow… a local trash folder and a selects folder for any keepers"（博客 101 转述） | 成立，与删除/Selects 指南一致。 | T-A1 #17、#20 |
| "template"（FEATURES 未细述；ARCHITECTURE 未述） | 笔记无此节，无勘误对象。官方模板=相册+收藏结构（+Next Capture 命名，博客 102），不含图片。 | T-A1 #28 |

## T-A3 三家历史存储对照（Q3 证据）

### Capture One（官方文档）

| 维度 | 会话模式 | 目录模式 |
|---|---|---|
| 调整存哪 | 图片所在文件夹的 `CaptureOne`/`SettingsNNN` 子文件夹，每张图 `.cos` 设置文件（T-A1 #8–#10） | 库数据库内（T-A1 #42："stores adjustments… within the Catalog"） |
| 结构（收藏/相册）存哪 | `.cosessiondb`（T-A1 #6） | 目录数据库（`.cocatalogdb`，见备份指南 "The .cocatalogdb database file"） |
| XMP 存什么 | 仅元数据双向同步（Full Sync/Load/None 三档，默认见指南 Image 页；T-A1 #51），不承载调整 | 同左 |
| 历史步列表 | 官方未说明（变体指南只讲 settings BLOB 与虚拟表示；无 undo 步数/历史面板说明） | 同左 |

### LightCraft（本地源码 `0da998f2`，只读）

| 维度 | 做法 | 代码位置 |
|---|---|---|
| 当前调整存哪 | 图库内存 `Photo.develop: Arc<DevelopSettings>`，持久化=快照+日志（catalog.snap/catalog.log） | `crates/catalog/src/model.rs:248`；`journal.rs:1-36` |
| 历史步存哪 | 同一照片记录内 `Photo.history: Vec<HistoryStep>`，每步=全量设置快照 `{label, settings}`，上限 200 步，超限丢最旧 | `model.rs:218-222,253-254`；`lib.rs:73`；`lib.rs:728-746`（PushHistory 截断+游标语义） |
| 提交语义 | 每次编辑=`Op::Batch{SetDevelop, PushHistory}`；滑杆拖动=begin/end_interaction 合并为一步（先静默恢复原值再提交终值） | `engine/src/lib.rs:925-931`（develop_op）；`:934-954`（interaction） |
| 持久化时机 | 每顶层命令后 `persist()` 一次 append+fsync；失败则命令报 NotSaved（内存已改，排队重试） | `engine/src/lib.rs:557-578`（run_command）；`library.rs:610` |
| 单写者 | `<library>/catalog.lock` OS 文件锁 + `catalog.lock.owner` 持有人提示；崩溃由 OS 释放，残留文件永不算 stale | `catalog/src/lock.rs:1-34` |
| XMP 角色 | 可选 sidecar（`<stem>.xmp` 或 `<file>.xmp`），默认每次改动自写（auto_write），owned-merge（自有属性重写、外来逐字节保留），读只取元数据+`crs:` 近似 | `engine/src/sidecar.rs:1-24`；`meta/src/xmp_merge.rs`；FRAMEWORK.md §6 |
| 图库唯一真相 | catalog 单真相；sidecar 是可选项（"catalog 单真相 + 可选 sidecar"，FRAMEWORK.md C3） | `engine/src/lib.rs:563-576` |
| 批量粘贴 | 单 `Op::Batch` 一次提交（paste/sync 拼 ops vec 后一次 commit） | `engine/src/cmd/develop.rs` paste/sync（见 FRAMEWORK-TABLES T-F2） |
| 预览缓存键 | 128 位：content_key（文件内容）+ settings hash64 + 尺寸桶 + RENDER_CACHE_VERSION + 相机配置键（+降噪盐）；photo id 亦折入内存 key（防 A/B 串图） | `engine/src/media.rs:1215-1260`（build_job）；`develop/src/lib.rs:59`（hash64） |
| 磁盘缩略图 | `<library>/thumbs/<2hex>/<32hex>.lcthumb`（JPEG q90），预算超限剪到 80%，7 天 STALE | `engine/src/library.rs:565`（attach 路径）；`preview/src/disk.rs:42-52` |

### darktable（HISTORY-COMPAT.md，只作对照）

| 维度 | 做法 | 出处 |
|---|---|---|
| 两处存 | DB（`history`/`masks_history`/`module_order`/`history_hash` + `images.history_end`）与原图旁 `<file>[ _NN].xmp` | HISTORY-COMPAT §0 |
| 写时机 | pref 三档 never/lazy/always，默认 on import | 同上 |
| 参数打包 | 整块 POD 内存镜像→DB BLOB→XMP hex（>100B 可 zlib+base64 加 gz 前缀）；无端序处理 | 同上 §3 |
| 冲突 | 无自动裁决；crawler 按 write_timestamp vs mtime（容差 2s）检出，用户四选一 | 同上 §0 |

## T-A4 Q3 三选项比较矩阵（甲=只存 DB；乙=单图设置文件+DB 结构索引；丙=两处都存）

> 前提：A-12 后无 dt 互通义务；历史模型=我们自己的栈（条目=模块+参数+使能+多实例键+process 版本）；DB=会话库（Q4 结论 SQLite，见 T-A5）。

| 维度 | 甲 只存 DB | 乙 设置文件+DB（推荐） | 丙 两处都存 |
|---|---|---|---|
| 实现量（crate/lane） | 最小：dt-catalog 写路径 + 读路径。不新增 crate。B12' 内消化。 | 中：新增 settings 文件编解码（dt-history 内，JSON 文本）+ DB 只存索引/缓存 + 双向一致规则。B13 主体（3 lane，见 T-A7）。 | 最大：乙的全部 + dt 双写/冲突裁决（crawler 四选一同款）。至少 +2 lane，长期维护双真相。 |
| 批量粘贴 1 万张 | 单事务批量 UPDATE，最快（推断：SQLite 单事务万行写毫秒~百毫秒级；以 B13 实测为准）。 | 万个小文件写（fsync 风暴）或打包延迟写；明显慢于甲（推断）。可用"粘贴先写 DB 队列、后台刷文件"追近甲。 | 同乙（文件侧决定下限），另加 DB 写。最慢。 |
| 崩溃安全 | SQLite 事务保证；单文件原子语义成熟。 | 文件写用 tmp+fsync+rename 逐个原子；万级批量中途崩溃=部分文件新、部分旧，需"DB 队列"做续刷（设计见 §3）。 | 双真相崩溃=DB 与文件各说各话，需裁决器；dt 用 crawler 人工四选一，我们若自动裁决则语义复杂。 |
| 备份 | 拷库文件即可（含全部调整）；漏拷=全丢。 | 拷整个会话文件夹（含设置子文件夹）；可只拷某张图的图+设置文件做细粒度备份（C1 同款，T-A1 #36）。 | 同乙（文件侧已含全部），DB 可重建。 |
| 单张搬运（跨会话/跨机） | 需导出/导入命令（从 DB 抽一条再注入）；裸拷图=丢调整。 | 拷图 + 其设置文件（同一相对位置），目标会话浏览即见调整（C1 同款，T-A1 #7、#13）。零命令。 | 同乙。 |
| 文件磁盘上被挪走 | DB 路径失效=整条历史"失联"（需重链接流程）；挪图者必须懂 DB。 | 图与设置文件一起挪=调整跟走（相对位置不变即完整）；只挪图不挪设置=回默认（可诊断、可恢复）。 | 同乙（文件侧兜底）。 |
| 损坏波及面 | 库文件坏=全会话调整不可读（需备份恢复；SQLite 有恢复手段但调整是 BLOB 行，细粒度修复难）。 | 单个设置文件坏=只影响该图（JSON 可人工修；坏文件可删回默认）；库坏=结构/索引坏，调整可从文件重建。 | 最小（互为备份），但"以谁为准"需裁决规则。 |
| XMP 库依赖 | 不需要（元数据读 EXIF 直读；导出嵌入标准字段手写）。 | 不需要（同左）。 | 若"两处"指 DB+XMP，则需要 XMP 库（A4a 复活，+1 lane + 构建依赖）；若指 DB+自有设置文件，则不需要。 |
| 与 LC"图库为真相"合不合 | 完全合（LC 即此形：catalog 单真相，sidecar 可选）。 | 改造：真相拆两层——调整真相=设置文件，结构/索引/缓存真相=DB。LC 的 commit/persist/undo 骨架可复用（T-F10 #10/#11），持久化目标一分为二。 | 不合（LC 明确单真相；dt 双存正是 LC 放弃的形态）。 |
| 用户可见心智 | "调整在库里"，拷图即丢调整（与 C1 用户预期相反）。 | "调整跟着图走"（C1 会话心智，用户已选 C1 模型，A-14）。 | 同乙，但偶发"DB 与文件不一致"提示（dt crawler 心智），支持成本高。 |

**XMP 结论**：第 0 期不需要 XMP 库、不写 XMP。元数据（星级/色标/关键词/IPTC）存设置文件（随图走）+ DB 索引（供检索）；导出时把标准字段嵌入产物（手写 EXIF/IPTC，不依赖 XMP 库）。跨软件元数据互通（LR/C1 读我们的星级）排 C 期"标准 XMP sidecar（只含元数据、不含调整）"，复用 LC owned-merge 纪律（T-F10 #13）。

## T-A5 Q4 会话库存储比较（SQLite vs 快照+日志 vs 结合）

> 前提：A-12 后无 dt 数据库互通义务；单会话库规模按 10 万张估；SQLite 经 rusqlite + vendored（bundled）SQLite，无系统依赖，SQLite 本体公有领域，GPL-3.0 下可用。

| 维度 | SQLite（WAL，推荐） | LC 式快照+只追加日志 | 两者结合（SQLite 主存 + op 日志） |
|---|---|---|---|
| 批量提交耗时 | 单事务万行 UPDATE，毫秒~百毫秒级（推断，B12' 实测）；WAL 追加写。 | 单 Batch 一次 append+fsync（LC 实证形态）；但快照是全库 JSON 重写（2000 条/16MB 触发，journal.rs:88-92），10 万张快照=百 MB 级 JSON 序列化（推断：秒级卡顿，后台化可掩盖）。 | 同 SQLite（热路径）；日志只作审计/undo 延长，无性能收益。 |
| 崩溃安全 | 事务+WAL，业界标准语义；SQLite 自带恢复。 | 四规则 crash-safe（journal.rs:11-33），LC 自证；但实现=我们重写 709 行 journal + 移植全部 corner case。 | SQLite 已给崩溃安全，日志层多余。 |
| 单写者锁 | 文件锁（LC lock.rs 改造：`session.lock` + owner 文件）+ SQLite 自身锁双保险。 | 同左文件锁（LC 原样）。 | 同左。 |
| 备份=拷文件 | WAL checkpoint 后拷单文件即可（或拷 -wal/-shm 全套）；`VACUUM INTO` 可产单文件快照。 | 拷 snap+log 两文件（或 compaction 后只拷 snap）；"拷一个文件就行"不成立（永远至少两个， compaction 时机不定）。 | 拷 SQLite 文件 + 日志文件（更麻烦）。 |
| 智能相册/检索查询 | SQL 直接表达（评分/关键词/相机/日期/文件夹多维过滤+排序+分页）；10 万行索引毫秒级（推断）。 | 自写 query（LC 有 query.rs，但过滤=内存全表扫描；10 万张常驻内存的 Photo 记录≈数十 MB 起，推断）。 | 同 SQLite。 |
| 10 万张体积 | 行存+索引，紧凑（推断：数十 MB；缩略图另在 Cache/ 不入库）。 | JSON 文本全量快照（每张=develop 全量 JSON + history 全量快照×步数×200 上限；推断：GB 级，需 history 截断/压缩，LC HISTORY_LIMIT=200 即此压力的形状）。 | 同 SQLite + 日志增量（更大）。 |
| 实现成本/风险 | rusqlite 成熟；schema 设计+迁移（`PRAGMA user_version`）+ DAO 层；风险低。B12' 4 lane 含此。 | 移植 journal/store/lock（~1000 行）+ 自写索引/查询/分页；风险=重造 SQLite 的查询面。至少 +3 lane 且长期背 corner case。 | 两套持久化语义+一致性规则；成本最高，无对应收益。 |
| 测试手段 | SQL 语义断言（行数/行内容）+ 并发写 + 崩溃注入（kill -9 后重开校验）+ `PRAGMA integrity_check`。 | LC 有 property 测试（log 重放确定性）；我们需重写整套。 | 两套都要测。 |
| 整包搬走 | 库单文件随会话文件夹走（C1 同款，T-A1 #33）。 | snap+log 随走（亦可，但两文件+ compaction 状态不定）。 | 同 SQLite，多余文件。 |
| 与 LC 复用关系 | 不复用 journal/store（LC 持久化层整体不取，与 FRAMEWORK.md F5 结论一致：SQLite 代差已定）；复用 lock 语义、Op/Batch/undo 骨架（内存形态）、hash64/process 规则。 | 全取 LC catalog（含 query/tally/folders 子系统），但查询/体积两项在 10 万张下是已知短板（推断）。 | — |

## T-A6 Q5 LightCraft 落点表（每个会话一个库）

> LC 引擎一次只持一个 library（`Session.library`，open_library 换库）；多会话=多引擎实例（每窗口一 Session），LC 代码按会话复用天然成立。

| LC 部件 | 放会话里 | 放应用层 | 复用方式 | 代码位置 |
|---|---|---|---|---|
| catalog（库记录） | ✅ 会话库 SQLite（替代 journal 文件对） | — | 内存 Op/Batch/undo 骨架复用；持久化换 SQLite | `catalog/src/lib.rs:614` apply；`engine/src/lib.rs:587` commit |
| journal 快照+日志 | —（不取） | — | 不复用（T-A5 结论） | `catalog/src/journal.rs` |
| 单写者锁 | ✅ 会话根 `session.lock` + owner 文件 | — | 改造复用（T-F10 #9）：锁文件名换，语义照搬 | `catalog/src/lock.rs` |
| 磁盘缩略图 | ✅ 会话 `Cache/Thumbs/`（内容键，可重建，备份可略） | — | 改造复用（T-F10 #7）：后缀/预算换 | `preview/src/disk.rs`；挂载 `engine/src/library.rs:565` |
| 内存预览/LRU/JobPool | ✅ 每会话引擎实例各持一份（随窗口） | — | 照搬/改造（T-F10 #5、#6、#8） | `preview/src/{pool,lru,lib}.rs` |
| 预览缓存键 | ✅ 不带会话标识（缓存目录已按会话隔离；键=内容+设置hash+尺寸+版本，LC 原样） | — | 照搬 | `engine/src/media.rs:1215-1260` |
| compaction | ✅ 会话库 `auto_checkpoint`/定期 VACUUM（SQLite 形态） | — | 自写（LC SnapshotPolicy 不取） | （新）dt-catalog |
| 内存预算/WorkGate | ✅ 每引擎实例一份（多会话窗口各一份预算，按窗口数均分或 LRU 抢占，B15 定） | 全局上限（多实例之和钳） | 改造（T-F10 #4） | `engine/src/memory.rs` |
| 命令注册表/execute/undo/activity | ✅ 每会话引擎实例 | — | 改造（T-F10 #10、#11）：命令集按 dt+会话重写 | `engine/src/cmd/mod.rs`；`lib.rs:512` |
| process 版本/hash64 | ✅ 设置文件字段 + 缓存键维 | — | 改造（T-F10 #12） | `develop/src/settings.rs:21-100` |
| 最近会话/模板/偏好 | — | ✅ 应用层 prefs（`~/Library/Application Support/<App>/`） | 自写（LC 无会话概念，无对应物） | — |
| XMP owned-merge | —（第 0 期不做 XMP） | C 期标准元数据 sidecar 时取 | 延期（T-F10 #13） | `meta/src/xmp_merge.rs` |

## T-A7 Q7 波次影响全表（A/B 逐波；C/D 只列受影响项）

> 基线：FRAMEWORK.md T-F11（A 10 波 20 lane 51.5h；B 20 波 80 lane 220h；合计 100 lane 271.5h）。下表 lane×小时按 PLAN 口径（A 波 2–3h/lane，B 波 2–3h/lane；原值见 PLAN §3）。

| 波 | 原内容（T-F11 后） | 新内容 | lane（原→新） | 小时（原→新） |
|---|---|---|---|---|
| A1 | 不变 | 不变（LICENSE 已定 GPL-3.0-or-later，A-3） | 1→1 | 2→2 |
| A2 | 空壳按 T-F9 新布局 | 不变（布局 T-F9 维持，见 §6；会话不增 crate，只增 dt-catalog/dt-engine 内模块） | 2→2 | 4→4 |
| A3 | 模块描述与自动发现 | 不变（半成品在 stash，恢复后照跑） | 3→3 | 7.5→7.5 |
| A3R | 重排+分层检查+testkit | 不变 | 2→2 | 5→5 |
| A4a | XMP 库选型三测 | **取消**（第 0 期无 XMP；元数据 EXIF 直读并入 B15，不加 lane） | 1→0 | 3→0 |
| A4b | dt 参数布局+迁移链+历史读 | **重做=我们自己的历史模型**：历史栈类型（模块+参数+使能+多实例+process）+ settings 文件 JSON 编解码 + hash/版本号规则。不做 repr(C)、modversion 链、blend v15 链。对照夹具改为"单向手写 dt XMP（只写不读）"供 oracle 用。 | 3→2 | 9→6 |
| A5 | oracle 对照工具 | 微调：夹具改手写 dt XMP（A4b 产出）；脚本/门不变，验收对照仍是 dt 官方版 | 2→2 | 5→5 |
| A6 | Apple 边界 | 不变 | 1→1 | 2→2 |
| A7a | 命令分发口 | 不变（会话命令在 B12' 注册，不加 A7a lane） | 3→3 | 8→8 |
| A7b | 视口与输入 | 不变 | 2→2 | 6→6 |
| **A 小计** | 10 波 20 lane | **9 波 18 lane（A4a 取消）** | 20→18 | 51.5→45.5 |
| B1 | 管线内核 | 不变 | 3→3 | 9→9 |
| B2 | rawspeed 解码 | 不变 | 2→2 | 6→6 |
| B3–B11 | 21 模块 | 不变（参数=我们自己的布局；dt 官方版仍是像素对照） | 38→38 | （原值和，见注1） |
| B12 | 历史读（XMP→栈） | **替换=会话包与库（B12'）**：会话创建/打开/锁/SQLite schema（照片/收藏/相册/索引）/模板/校验/备份命令/CLI 全套。历史读移出第 0 期。 | 3→4 | 9→12 |
| B13 | 历史写与图库 DB | **重做=历史写与设置文件**：写 settings 文件（tmp+rename）+ DB 索引更新 + process 版本/升级命令 + 单张搬运（导出/导入调整）+ 崩溃续刷队列。不做 dt 写回/owned-merge。 | 4→3 | 12→9 |
| B14 | 蒙版与混合基础 | **退回基础**：启用位+整图不透明度混合；drawn/parametric/栅格/组合排 C（C-6）。 | 5→2 | 15→6 |
| B15 | 导入图库缩略图 | 内容换=会话浏览：导入（复制默认/引用可选）+ 缩略图（三级+磁盘缓存，F11 的 +2 保留）+ 评分色标 + 10 万行虚拟列表 + Capture/Selects/Trash/Output 文件夹行为 + EXIF 直读（并入 A4a 残余）。 | 6→7 | 18→21 |
| B16 | 导出 | 微调：默认落点=会话 Output/（可改）；其余不变 | 4→4 | 12→12 |
| B17 | 界面壳与面板生成 | 不变 | 5→5 | 15→15 |
| B18 | 视口与暗房 | 不变 | 4→4 | 12→12 |
| B19 | 灯箱胶片条菜单 | 内容加=会话浏览器：会话树/收藏/相册/智能相册面板 + 灯箱网格（原内容保留）。 | 4→5 | 12→15 |
| B20 | 闭环验收 | 微调：验收脚本走会话（建会话→导入→改→导出到 Output→备份恢复）；"打开 dt 修过的 3 张图"改为"对照 dt 官方版同参数渲染"（无 dt 历史读，改手写 dt XMP 对照）。 | 2→2 | 6→6 |
| **B 小计** | 20 波 80 lane | **20 波 79 lane（B12 替换，B14 缩）** | 80→79 | 220→217 |
| **A+B 合计** | 100 lane 271.5h | **97 lane 262.5h；含自审 ×1.2 ≈ 315h ≈ 40 个 8h 日** | 100→97 | 271.5→262.5 |
| C-4 | 图库检索与标签 | 范围减：层级标签/IPTC 关键词保留；集合/搜索语法部分已在 B12'/B19 做（智能相册基础），C-4 只做高级（全文/地理/去重）。 | ≈估减 1 波 | — |
| C-5 | 批量导出 | 加：标准 XMP sidecar（只元数据）+ HEIC/AVIF 等编码器（原内容保留）。 | ≈加 1 波 | — |
| C-6 | 完整蒙版 | 加：B14 退回的 drawn/parametric/栅格/组合。 | ≈加 1 波 | — |
| C-9 | AI 与接口 | 加：dt 历史读（B12 移出的内容，不排期，按 #34；C-9 只挂名不估时）。 | 挂名 | — |
| D | — | 不变。 | — | — |

注1：B3–B11 lane/小时原值：B3 6×2=12h、B4 4×3=12h、B5 5×3=15h、B6 3×2=6h、B7 4×2.5=10h、B8 4×3=12h、B9 3×2=6h、B10 3×3=9h、B11 6×2=12h，合计 38 lane 94h。本次不动。
行加总验算：A：2+4+7.5+5+0+6+5+2+8+6=45.5 ✓。B：9+6+94+12+9+6+21+12+15+12+15+6=217 ✓（B3–B11 以 94h 一项计）。合计 45.5+217=262.5 ✓。lane：A 1+2+3+2+0+2+2+1+3+2=18 ✓；B 3+2+38+4+3+2+7+4+5+4+5+2=79 ✓。

## T-A8 Q6 命令清单（"一切皆命令"口径；develop.* 沿用 LC 形态，面板描述即 schema）

| 命令 | 参数 | 写什么 | 说明 |
|---|---|---|---|
| session.new | name, dir, template? | 建会话文件夹四件+库+锁 | 模板=相册/收藏结构（T-A1 #28） |
| session.open | path(.lmsessiondb 或会话文件夹） | 取单写者锁，载库 | 无库文件夹→按"就地建会话"流程（§2） |
| session.close | — | 释锁，刷脏，checkpoint | 脏数据先落盘 |
| session.verify | — | 只读诊断+可修项 | 对 T-A1 #39 |
| session.backup | dest | 拷整包（除 Cache/Trash 可选略） | 对 T-A1 #36 |
| session.restore | backup, dest | 整包拷回+打开 | 对 T-A1 备份指南 |
| template.save | name | 存结构到应用模板库 | 不含图片（T-A1 #28） |
| library.import | src[], dest(Capture), mode(copy/reference), backup?, naming?, adjustments? | 复制/引用+建库记录+缩略图任务 | 默认复制进 Capture（§2）；引用=收藏式（§2） |
| library.sync | folder | 扫描增删，补库记录 | 对目录指南 Synchronize（T-A1 附件节） |
| photo.moveToSelects | ids | 物理移动到 Selects/+设置文件 | C1 同款（T-A1 #17） |
| photo.delete | ids | 移进 Trash（图+设置文件） | C1 同款（T-A1 #20）；Trash 内只读 |
| photo.restore | ids | 从 Trash 移回原位（库记原路径） | 对 T-A1 #23 |
| trash.empty | — | 永久删除 Trash 内源文件+设置 | 不可撤回（T-A1 #21） |
| photo.rate/photo.label/photo.flag | ids, value | 设置文件+DB 索引 | 元数据随图走（§3） |
| album.create/smart.create/favorite.add/remove | — | 库结构表 | 存库（T-A1 #6 同款） |
| develop.set/merge/reset/copy/paste/sync | id(s), patch/groups | 设置文件+DB 缓存键+历史步 | LC 形态（T-A3）；滑杆=begin/end_interaction |
| process.update | ids | settings 文件 process 升号+重渲 | LC "Update to Current Process" 同款 |
| export.process | ids, recipe | 写 Output/（默认）+进度 | 默认落点 Output（T-A1 #15） |
| adjustments.export/import | ids, file/dir | 单张调整旁路（跨会话/跨机） | 乙的搬运命令（§3） |
| history.goto | id, step | 游标移动（LC history_cursor 同款） | 不删后续步（T-A3） |

## T-A9 没查到的与版本差异（Q9 证据部分）

| # | 查什么 | 查过什么 | 结论 |
|---|---|---|---|
| 1 | Output 可排除在浏览外（塔台称指南写过） | 所取 Sessions 指南 2025-04 版全文 grep Output/exclude；导入/Folders/Selects 指南 | **本版无此句。** 可能塔台所见版本不同，或在 Folders/Library 文章他处。标版本差异，查不到。 |
| 2 | 同一会话开两次（锁/单写者） | Sessions 指南（多会话节只讲开不同会话的新窗口）、目录锁节（未细取）、社区帖标题 | **官方未说明。** 我们的单写者锁是自有设计（LC lock.rs 改造），非 C1 对齐。 |
| 3 | 单张图跨文件夹拖拽时调整是否跟走 | Sessions 指南（只讲整包相对结构搬运）、Selects/删除指南、103（Export Originals 发 RAW+调整）、社区个案（Selects 移动丢蒙版个案，非官方） | **官方未直接说明。** 我们的设计：库内移动=图+设置文件一起搬（命令保证）；库外裸搬=按下式 §3 处理。 |
| 4 | `.cos`/设置文件格式细节 | 全部已取官方文档（文档只到"settings file"/"BLOB of data"一层） | **官方未说明。** 我们的设置文件格式自定（JSON），不兼容 .cos（A-12 后无此义务）。 |
| 5 | `SettingsNNN` 命名规则 | 备份指南仅见 `Settings165` 一例 | **推断=版本号**（16.5→165）。我们的设置子文件夹名自定（§2），不跟随。 |
| 6 | Trash 容量/自动清空/保留期 | 删除三指南 + Sessions 指南 | **官方未说明**（只有手动 Empty）。我们：第 0 期只做手动清空。 |
| 7 | Catalog 模板内容/会话转目录细节 | 目录指南（模板节标题级；导入会话节已取 T-A1 #46） | 与第 0 期无关，未细取。 |
| 8 | LC 三个性能数（0.72s/1s/0.5s） | FRAMEWORK.md §13 已查：docs+crates 全文 grep 无命中 | **查不到**（沿用 FRAMEWORK 结论；A-10 门待实测）。 |
| 9 | SQLite 10 万行/批量粘贴实测数 | 未实测（本 lane 禁构建禁跑） | **推断**，B12'/B13 实测填数。 |
| 10 | support.captureone.com 本体直取 | curl 直取=Cloudflare 挑战页（`Just a moment...`）；curl 经代理亦同 | 经 web.archive.org 2025 快照取文；链接给官方原文 URL，ASN 标注快照日期。 |
