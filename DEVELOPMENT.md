# 番茄端碗（FanqieDuanwan）开发者文档（Windows 版）

面向构建、修改和调试本项目的开发者。用户使用说明见 [README.md](README.md)。

> **核心设计**：Rust 原生核心在 Flutter 进程内运行，UI 通过 flutter_rust_bridge 直接调用；同一分发器另开 loopback HTTP 适配器（`127.0.0.1:8080`），继续服务内置 Web UI、`/api/*` 桥和 `/src/*` 漫画图。不需要自建服务器，不需要 root；签名、解密和本地缓存由本机完成，但在线内容仍需访问上游。
>
> **本版定位**：仅发布 **Windows 桌面版**（x64）。自 v0.9.123 起已移除 `android/` 构建目标，不再保留或发布 Android APK；`ios/` 等同理不在此版本范围内。

---

## 目录

- [架构总览](#架构总览)
- [项目结构](#项目结构)
- [构建环境](#构建环境)
- [编译 Rust 原生核心](#编译-rust-原生核心)
- [构建加密播放库](#构建加密播放库)
- [构建 Windows 安装包](#构建-windows-安装包)
- [安装运行](#安装运行)
- [Windows 原生核心集成](#windows-原生核心集成)
- [API 对接说明](#api-对接说明)
- [数据模型](#数据模型)
- [页面说明](#页面说明)
- [已知问题与调试](#已知问题与调试)
- [开发计划](#开发计划)

---

## 架构总览

```
┌──────────────────────────────────────────────────┐
│                    Flutter App (Windows)          │
│                                                  │
│  ┌──────────┐   ┌────────────┐   ┌────────────┐  │
│  │ UI 页面  │──▶│ ApiClient  │──▶│  Backend   │  │
│  │(阅读/播放)│   │(归一化解析) │   │ Transport  │  │
│  └──────────┘   └────────────┘   └─────┬──────┘  │
│                                        │         │
│  ┌──────────┐   ┌────────────┐         │         │
│  │ Library  │   │  Backend   │         │         │
│  │  Store   │   │  Service   │─────────┘         │
│  │(历史/时长)│   │(核心初始化) │                  │
│  └──────────┘   └─────┬──────┘                   │
└───────────────────────┼──────────────────────────┘
                        │ flutter_rust_bridge (FFI)
                        ▼
              ┌───────────────────────────┐
              │    Rust 核心 fanqieduanwan_core    │
              │    fanqieduanwan_core.dll (Windows)│
              │ 签名 · 解密 · 设备池 · 分发器│
              └──────┬─────────────┬──────┘
                     │             │
      loopback HTTP  │             │ HTTPS (reqwest)
      127.0.0.1:8080 │             ▼
                     ▼      上游 API
          内置 Web UI / /src/* 漫画图
```

### 数据流

1. **启动**：`main.dart` → `BackendService.start()` 将配置、过滤器、Web 页面及其 CSS/字体、插件部署到应用私有目录 → 通过 flutter_rust_bridge 在进程内初始化 Rust 核心（`fanqieduanwan_core.dll`）→ 轮询 `/health` 直到 200。核心没有独立进程，也不再有 Kotlin/JNI 桥或桌面可执行文件。
2. **请求**：UI 页面 → `ApiClient` → `BackendTransport`（默认 `RustBackendTransport`，经 flutter_rust_bridge 直调 Rust 分发器；Web/测试用 loopback HTTP）→ 同一 Rust 分发器完成签名（Argus551）、设备池管理、请求上游、解密内容 → 返回归一化 JSON。
3. **存储**：历史和阅读时长走 `LibraryStore`（Hive）。
4. **桌面播放**：视频/听书播放走 media_kit（libmpv）。桌面没有 Android 的 ExoPlayer 原生宿主，由 Rust 核心 loopback 的 `/media/play` 端点按 Range 回源、边下边解密，再交给 libmpv 渲染。

---

## 项目结构

```
fanqieduanwan/  (仓库 slug 为 byazlle/winFQAPP)
├── lib/                             # Flutter UI、模型和本地状态
│   ├── main.dart                    # AppBootstrap + RootShell（宽屏自适应导航）
│   ├── models/                      # 数据模型与响应解析
│   ├── pages/                       # 阅读、播放、搜索、首页等页面
│   ├── services/                    # 请求、缓存、历史和平台服务
│   │   └── brand.dart               # 品牌常量：名称、副标题、主色与渐变
│   ├── widgets/                     # 按界面分组的组件与通用组件
│   │   └── brand/glass.dart         # 玻璃拟态基元：背景、玻璃面板、品牌标记
│   └── src/rust/                    # FRB 生成绑定
├── rust/                            # fanqieduanwan_core 源码、协议夹具和 Rust 测试
├── native/                          # CENC 流式 C 解密库、FFI 与 CMake
├── assets/                          # 配置示例、Web UI、插件、图片和动画
│   └── branding/                    # 品牌母版图与图标生成说明
├── test/                            # Flutter 测试及 Node 主机回归
├── scripts/                         # 构建、验证和资源生成；见 scripts/README.md
├── windows/                         # Windows 工程与 Inno Setup 安装脚本
│   └── installer/                   # 安装向导品牌图（164×314 / 55×55 BMP）
├── .github/workflows/               # Windows 构建与原生库 CI
├── flutter_rust_bridge.yaml         # FRB 代码生成配置
└── pubspec.yaml                     # Flutter 版本、依赖与资源声明
```

> **仓库不含原生二进制**：`fanqieduanwan_core.dll` 和 `libshortplay_crypto`（C 解密库）均被 Git 忽略。
> 前者由 `rust/` 中的 Rust 源码经 `scripts/build_rust_backend.*` 重建为 Windows cdylib；
> C 解密库在编译 Rust 核心时一并编入核心，桌面不再有独立的 `.so`/`.dll` 解密库文件。
>
> 体积参考：Rust 核心 Windows release 产物 `fanqieduanwan_core.dll` 的实测大小见 CI 产物报告（约 5–6 MiB）。

---

## 构建环境

### 环境要求

| 工具 | 版本 | 用途 |
|---|---|---|
| Flutter | 3.44.6 (stable) | 构建 App |
| Dart SDK | 3.12+ | 随 Flutter |
| Rust | stable (cargo/rustc) | 编译原生核心 `fanqieduanwan_core`（Windows cdylib） |
| flutter_rust_bridge | 2.13.0 | 生成 Flutter/Rust 绑定 |
| Visual Studio (MSVC) | 含「使用 C++ 的桌面开发」 | 编译 Rust 核心与 C 解密库（MSVC 工具链） |
| Inno Setup 6 | 最新 | 打包 `fanqieduanwan-setup-x64.exe` 安装程序 |
| VC++ 运行库 | 2015–2022 | libmpv 依赖，由安装程序一并部署 |

> Windows 下推荐用 Visual Studio Installer 安装 MSVC v143 工具集与 Windows 10/11 SDK。
> Rust 核心的 C 解密库使用 CMake 在 Windows 上编译，无需 Android NDK。

### 1. 编译 Rust 原生核心

`rust/` 是产品唯一的后端实现（crate `fanqieduanwan_core`）。构建脚本会先用
`flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` 生成 Dart/Rust 绑定，
再用 MSVC 工具链编译为 Windows cdylib `fanqieduanwan_core.dll`，供 Flutter 通过 FFI 在进程内加载。

Windows PowerShell：

```powershell
.\scripts\build_rust_backend.ps1 -HostLib
```

Linux / macOS（仅交叉验证绑定或核心逻辑，不产出 Windows 安装包）：

```bash
./scripts/build_rust_backend.sh
```

常用开关：`-SkipCodegen` 跳过绑定生成（绑定已是最新时），`-HostLib` 额外构建桌面 cdylib，
`-Profile debug` 选择 debug 配置。`-HostLib` 在 Windows 上即编译 `fanqieduanwan_core.dll`。

`rust/testdata/` 的黄金向量由维护者的离线对照环境生成后随仓库分发；
正常构建与 CI 不依赖任何私有检出，也不需要额外的外部工具链。

> ⚠️ `assets/config/` 只包含 `config.json`、`filter.json`、`device_pool.example.json`
> 三个确定的配置文件。真实设备池 `device_pool.json` 里带 `secret_key`，**不随仓库或安装包分发**；
> 首次启动时由 `BackendService` 从示例初始化，此后设备实际注册的池保存在应用私有目录，
> 后续资源升级会保留它。

### 2. 构建加密播放库

`native/` 提供自行实现的 CENC MP4 流式解密核心，作为 Rust 核心的一部分在 Windows 上编译进
`fanqieduanwan_core.dll`，支持边读边解密与拖动，不再需要下载外部预编译 crypto 库。

实现范围、支持的 MP4 格式、主机回归和设备验证边界见 [C 库说明](native/README.md)。

### 3. 构建 Windows 安装包

完整构建（codegen + Rust 核心 dll + Flutter Windows + InnoSetup 安装包）：

```powershell
.\scripts\build_windows.ps1 -Profile release
```

产物为 `build/windows/x64/runner/Release/` 下的运行时，经 InnoSetup 打包为
`fanqieduanwan-setup-x64.exe`（位于仓库根的 artifact 输出目录）。脚本会自动：

1. 生成 FRB 绑定；
2. 用 MSVC 编译 `fanqieduanwan_core.dll` 与 C 解密库；
3. `flutter build windows --release`；
4. 下载并随包附带 VC++ 2015–2022 运行库（已装则跳过）；
5. 调用 Inno Setup 生成安装程序。

### GitHub Actions 云端编译

打开仓库 **Actions → Build Windows (cloud)**，点击 **Run workflow** 即可从源码构建；
`master` 上的应用、原生库及构建配置变更也会自动触发。运行成功后，在该次运行的 **Artifacts**
中下载 `fanqieduanwan-windows-setup`（含 `fanqieduanwan-setup-x64.exe`）。

[工作流](.github/workflows/build-windows.yml) 固定 Flutter `3.44.6`、Rust 工具链与
flutter_rust_bridge `2.13.0`。Rust 核心与 C 解密库都会在 runner 上编译；原生加密库对齐检查
（16 KiB / ARM 页对齐在 Windows 上不适用，此处校验的是 DLL 链接与符号导出）通过后产出安装包。

每次构建运行 Rust、Web 与诊断脚本测试、Flutter 静态分析与完整单元/组件测试。
产品构建不依赖任何私有检出或额外工具链；`rust/testdata/` 的黄金向量随仓库分发，不进入产品构建。

打 `v*` tag 推送后，工作流会额外在 **Releases** 页发布同一安装包，并附 `SHA256SUMS` 与
`verify-report.json`（构建信息、核心库 SHA-256、对齐等校验原始报告），可自行核对。

> ⚠️ fork（无发布签名密钥）构建出的安装包未做代码签名，仅用于检查，不能作为正式发布包；
> 在另一台 Windows 上安装前请确认来源。正式签名由仓库维护者在有密钥的环境下完成。

### 4. 安装运行

双击 `fanqieduanwan-setup-x64.exe` 按向导安装（会自动部署 VC++ 运行库依赖），从开始菜单或桌面快捷方式启动。

首次启动：App 将运行时资源部署到应用私有目录，通过 flutter_rust_bridge 初始化 Rust 原生核心，
健康检查通过后进入主界面。已有缓存时也可在启动页面直接进入离线阅读。

---

## Windows 原生核心集成

### 部署流程（`BackendService._deploy`）

1. 将 `config.json`、`filter.json`、`device_pool.example.json` 部署到应用私有目录 `files/backend/config/`。
2. 首次启动时用示例初始化 `device_pool.json`；以后保留后端注册并保存的实际设备池。
3. 从 Flutter 资源清单枚举并部署全部 `filters/`、`web/`、`plugins/` 文件，包含 CSS 和字体。内容变更时替换旧资源。
4. 运行时资源不含任何可执行后端二进制；Rust 核心以 `fanqieduanwan_core.dll` 随 Windows 构建打包，在进程内加载。

### 启动流程（`BackendService.start`）

```dart
// 默认：flutter_rust_bridge 直调 Rust 核心（进程内，无独立进程）
await rust.init(
  configPath: ..., poolPath: ..., filterPath: ..., runtimeDir: ..., port: 8080,
);
// Web / 测试：同一分发器另开 loopback HTTP 适配器，供浏览器入口与 /src/* 资源
```

- 并发 `start()` 等待同一次完整启动，`stop()` 会等待进行中的部署与启动结束再清理。
- 健康检查默认总时限 15 秒，单次请求覆盖连接、响应头和响应体的时限，失败后间隔最多 300 毫秒重试。
- 启动诊断写入 `backend.log`。核心没有独立进程：显式 `stop()` 调用 Rust 的 `shutdown` 释放运行时，不存在子进程退出或终止信号逻辑。

### 进程内加载形态（与 SELinux 限制的对照）

Android 上 `untrusted_app` SELinux 域禁止执行 `app_data_file` 下的二进制，因此核心始终采用
「共享库 + 进程内加载」形态。Windows 没有这一限制，但本项目为跨平台一致仍采用同一形态：
`fanqieduanwan_core.dll` 由 Flutter 通过 flutter_rust_bridge 的 FFI 在进程内加载，不存在独立的后端可执行文件。

安装 MSVC 工具链后运行 Rust 构建脚本即可生成核心库：

```powershell
.\scripts\build_rust_backend.ps1 -HostLib
```

Rust 核心会使用配置文件推导运行目录，静态页面、过滤器和 `src/` 均按绝对路径加载；
loopback HTTP 适配器只绑定 `127.0.0.1`，`/health`、`/api/*`、`/src/*` 与 Web 入口共用同一分发器。

---

## API 对接说明

App 主要通过 `ApiClient` 调用后端 **`/api/*` 桥接层**（Rust 核心 `rust/src/endpoints/webui.rs`），首页推荐使用
`/api/v1/recommend/homepage`。漫剧首页使用 `tab_type=24`；听书使用现有音频播放接口，漫画首页使用真实漫画分类搜索。

客户端模型同时兼容归一化结果及部分旧版响应结构：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/v1/recommend/homepage?tab_type=&offset=&session_id=` | 首页分类推荐及游标分页 |
| GET | `/api/v1/search?query=&tab_type=&offset=&count=10` | 搜索页按分类请求：综合 `1`、小说 `3`、短剧/漫剧 `11`、漫画 `8`、听书 `2`，使用返回的游标；评分门槛仅筛选客户端已加载结果，不改变请求参数与游标 |
| GET | `/api/v1/books/{id}/detail` | 按作品 ID 精确查询名称、封面和类型；详情不可用时使用同一路径的 `/directory` 中的 `book_info` |
| GET | `/api/v1/series/{id}` | 短剧／漫剧系列详情：标题、简介、集数、播放量、分类，以及**演员表**（`data.video_data.celebrities`） |
| GET | `/api/v1/books/{id}/comments` | 书评列表与页级计数 |
| GET | `/api/v1/books/{id}/related` | 关联作品（原著小说 / 改编短剧） |
| GET | `/api/v1/books/{id}/tones` | 智能朗读音色与真人讲书 `audio_tones` |
| GET | `/api/v1/chapters/{id}/reviews` | 章评／段评 |
| GET | `/api/v1/chapters/{id}/paragraphs/{n}/reviews` | 段评，带上 `para_index` 供定位 |
| GET | `/api/v1/books/{id}/reviews?book_id=&group_id=&insert_comment_ids=` | 评论列表，段评的第二跳 |
| GET | `/api/v1/chapters/{id}/timeline` | 边听边读字幕；必须显式传 `genre` 与有效 `tone_id` |
| GET | `/api/v1/search?query=&tab_type=8&offset=&count=10` | 漫画专属搜索 |
| GET | `/api/v1/search?query=漫剧&tab_type=11&offset=&count=10` | 漫剧首页推荐耗尽后的搜索来源 |
| GET | `/api/v1/audio/play?book_id=&item_ids=&tone_id=0` | 听书播放模型和时长 |
| GET | `/api/search?source=番茄&query=&page=` | 旧版搜索桥接，仍供部分首页回退调用 |
| GET | `/api/detail?source=番茄&book_id=&tab=` | 详情（tab=听书 走有声详情） |
| GET | `/api/directory?source=番茄&book_id=&tab=` | 目录（短剧走剧集） |
| GET | `/api/v1/chapters/{id}/novel` | 小说图文正文，要求 `data.content_decrypted=true` |
| GET | `/api/content?source=番茄&item_id=&tab=` | 正文（小说/漫画/听书/短剧分发） |
| GET | `/api/content?source=番茄&item_id=&tab=短剧&mode=stream` | 短剧和漫剧视频流地址与内容密钥 |
| GET | `/api/resolve?url=` | 分享链接解析 |
| GET | `/api/download?source=番茄&book_id=` | 整本 TXT 下载 |
| GET | `/health` | 健康检查（返回设备池数量） |

**响应信封**：客户端接受 `code=200`（Web 桥接）或 `code=0`（上游兼容接口）的成功响应；
其他显式状态码或 `success=false` 视为错误。

**小说插图**：`ApiClient.chapterContent` 优先读取 v1 图文接口，失败时回退原纯文字正文。完整插图支持由 Rust 核心
`rust/src/endpoints/base.rs` 的解密实现提供，改动后运行 `scripts/build_rust_backend.ps1` 重建 `fanqieduanwan_core.dll`；
上游的 `c=1` 是加密标志，密文来自 JSON `data.content`。核心没有解密成功标记时，客户端回退文字。
该行为由 `rust/testdata/` 的离线黄金向量夹具保证一致。

**搜索分类与分页**：搜索页使用 `/api/v1/search` 请求所选分类，在拆分漫剧之前先选取对应的上游 tab，
再按条目实际 `kind` 筛选。综合保留全部作品；短剧、漫剧、漫画、听书分别只展示 `video`、`manju`、`manga`、`audio`。

**漫剧与漫画参数不同**：首页的漫剧为 `24`、看剧为 `8`、漫画为 `9`；搜索的视频为 `11`、漫画为 `8`、听书为 `2`。

---

## 数据模型

### `MediaItem`（归一化条目）

`MediaItem.fromRaw()` 兼容上游 API 的各种字段形状：

| 字段 | 来源优先级 |
|---|---|
| `id` | 小说/漫画/听书使用内容 ID；短剧/漫剧优先使用系列 `pseries_id`/`series_id`，单集结果保留 `episodeId` |
| `kind` | `book`/`video`/`manju`/`manga`/`audio`；合法显式类型优先，缺失时按结构化标识推断，否则为小说 |
| `title` | 高亮标题 → 外层标题 → 嵌套标题/书名 → `cell_name` |
| `cover` | `thumb_url` → `cover`/`cover_url`/`poster` |
| `author` | `author`/`author_name` |
| `badge` | 已保存的 `badge` → `category`/`type`/`cell_alias`/`card_tips` |
| `ep` | 已保存的 `ep` → `serial_count`/`item_count`/`episode_count` |

### `Chapter`（目录章节）

`chapterListWithVolume` 格式 → `itemId`/`title`/`volume_name`，按卷分组。

短剧和漫剧上游的 `data.episodes`、`item_data_list` 和 `lists` 也会统一转换为同一模型。

### `SearchTab`（搜索 tab）

`title` + `items[]`，支持嵌套 `video_data`、`book_data` 展开，并保留可选 `hasMore` / `nextOffset`。
漫剧根据 `genre=205` 或明确的类型标签识别。

---

## 页面说明

### 首页（`home_page.dart`）
- 提供推荐、小说、短剧、漫剧、漫画和听书分类；推荐页混排各类内容
- 优先调用真实 `/api/v1/recommend/homepage`，推荐接口不可用时回退搜索结果
- 宽屏（≥900）左侧悬浮导航栏，≥1200 展开为「图标 + 文字」；内容列宽随窗口分级（840/920/1080）
- 3 列封面网格；桌面端用顶栏按钮 / `F5` / `Ctrl+R` 刷新，不使用移动端下拉刷新

### 搜索（`search_page.dart`）
- 顶部搜索框（回车/图标触发）
- 输入 15 至 20 位纯数字自动按作品 ID 查找；`id:作品ID` 可显式查询
- 结果按 tab 用 ChoiceChip 切换；分类固定依次为综合、短剧、漫剧、漫画、听书
- 接近列表底部时按实际游标自动分页，按类型和作品 ID 去重
- 保存最近 20 条搜索；输入时显示联想词，空查询显示热搜词

### 作者主页（`author_page.dart`）
- 头像、昵称、作家等级徽章、粉丝数、简介
- 「全部作品」网格：封面、标题、`分类 · 完结状态 · 字数`
- 加载失败可重试

### 排行榜（`rank_page.dart`）
- 榜单：推荐榜 / 完本榜 / 巅峰榜 / 新书榜 / 漫剧榜 / 短剧榜
- 触底自动翻页，续页名次连续

### 详情（`detail_page.dart`）
- 左上封面（3:4）+ 右侧标题、`分类 · 完结状态 · 字数`、「原创」徽章
- 数据三栏：榜单、正在阅读人数、评分（含五星）
- 演员表：短剧／漫剧显示横向演员卡片
- 书籍简介三行折叠可展开，题材标签，`查看目录` 行与 3 章目录预览
- 书评区：评分卡 + 评论列表；「回复 N」可展开回复
- 底部：听书 / 下载 / 阅读（播放、续看）三键
- 宽屏（内容区 ≥1080）自动切两栏：左栏封面、标题、作者、阅读数据、标签与作品 ID；右栏简介、演职员、目录与评论。`DetailHero` 的 `column` / `coverWidth` / `showWash` 控制左栏形态

### 内容源（`content_sources_page.dart`）
- 设置 → 内容源：短剧 / 漫剧 / 漫画 / 小说 / 听书各自独立选择来源，持久化在
  `SharedPreferences` 的 `content_sources.v1`（来源列表 + 各类型当前源 + 自动容错开关）。
- `ContentSourceStore` 只负责“选哪个源”，不直接发内容请求；内置番茄源默认启用，
  红果 / 西饭 / 河马默认关闭，自定义源走通用 CMS 协议（`CmsSourceClient`）。
- 适配器：`SourceAdapter`（browse / search / detail）+ `SourceRouter`
  （按 `fallbackChain` 降级）。已实现 `CmsSourceAdapter`、
  `XifanSourceAdapter`（`xifan-api-cn.youlishipin.com`）、
  `HemaSourceAdapter`（`www.kuaikaw.cn` 的 `__NEXT_DATA__`）；
  红果网页版用 `PendingSourceAdapter` 保留接口，选中时明确提示。
- 浏览链路：`SourceBrowsePage`（列表 / 搜索 / 分页）→ `SourceDetailPage`
  （播放线路 + 分集）→ 复用 `PlayerPage`，通过 `contentLoader` 返回
  `{'video_url': 直链, 'key_hex': ''}`，不重写播放器。
- 番茄源仍走原有首页 / 搜索 / 详情 / 播放；第三方源从设置页的
  「浏览当前来源」进入，两套流程互不干扰。

### 阅读器（`reader_page.dart`）
- 加载解密后的图文正文，保留段落、插图和图注的原始顺序
- 插图保持原比例，分页时整张显示，点击进入全屏并可双指缩放
- 默认左右分页，可切换上下滚动；翻过章节末页进入下一章首页
- 字号、字重、字距、行距、段距、对齐、留白和四种阅读背景实时预览并保存
- 支持通过系统文件选择器导入 TTF、OTF、TTC 字体（单文件不超过 32 MB），也可切回系统字体
- 亮度可手动调整或跟随系统；菜单、排版、目录和缓存面板随阅读主题配色
- 目录支持搜索、倒序、当前章定位与缓存标记
- 章节正文解析上游 `<p idx>` 段落 ID，随结构化缓存持久化
- 底部“缓存”可下载后续 20/50/100 章；自动缓存上限 500 章或 80 MB，超出清理较久未读章节

### 播放器（`player_page.dart`）
- 短剧与漫剧共享播放器；漫剧保留独立历史类型
- 桌面走 media_kit（libmpv），解密流来自 Rust 核心 `/media/play` 的 Range 回源
- 自动连播（播完自动下一集）
- 控制栏三秒后自动隐藏；单击显示或隐藏，双击播放或暂停
- 支持搜索选集、上下集、快进快退 10 秒和全屏
- 全屏方向按视频比例决定；锁定后方向不再变化
- 0.75～2 倍速可持久保存，长按临时 2 倍速，松手恢复
- 桌面端提供键盘快捷键：上下方向键长按连续步进、空格播放/暂停、倍速记忆、音量调节（每项均保留可点击控件）

### 书架（`library_page.dart`）
- 阅读历史：支持列表或封面网格（含进度、集数）
- 清空功能；右上角“离线缓存”可直接打开已缓存书籍
- 设置 → 数据 → 章节缓存，可查看占用、删除单本或清空全部缓存

### 听书（`audio_page.dart`）
- 顶栏显示当前朗读模式（智能朗读 / 真人讲书）、状态圆点与更多菜单
- 边听边读字幕：按播放位置高亮当前句并预览下一句
- 操作行：语速 / 加入书架 / 下载 / 书评 / 更多
- 定时关闭（15/30/60 分钟）；后台播放与通知栏媒体控制（断开耳机/蓝牙时自动暂停）
- 播放秒数与章节定时保存，重新进入可续听

### 漫画（`comic_reader_page.dart`）
- 按接口顺序竖向阅读图片，支持章节目录和上下章
- 图片按需加载并限制解码尺寸；单张失败可重试，点图可放大
- 用“图片序号 + 图片内位置”记录进度；宽屏支持 2/3/4 页并排（窄窗口收敛为单页）

### 我的（`mine_page.dart`）
- 服务状态（健康检查）
- 后端地址展示
- 设置 → 关于：版本、源代码与反馈入口（番茄端碗当前托管在 `byazlle/winFQAPP`）

---

## 已知问题与调试

### 1. 原生库与验证

- Rust 核心编译为 `fanqieduanwan_core.dll` 并在进程内加载。先运行 `scripts/build_rust_backend.ps1 -HostLib` 生成核心库；
  黄金向量夹具随 `rust/testdata/` 分发，不参与构建。
- 加密播放使用 `native/` 中的 C 源码，随 Rust 核心在 Windows 上编译进 `fanqieduanwan_core.dll`。
- 生成核心库后构建 Windows 安装包，再用目标机验证 `/health`、搜索、阅读和加密视频播放。

### 2. 调试技巧

```powershell
# 查看后端日志（App 写入应用私有目录）
# 路径形如 %APPDATA%\byazlle\FanqieDuanwan\logs\app.log ；可用设置 → 服务 → 日志 直接查看
# 端口转发测试（核心起来后）
curl http://127.0.0.1:8080/health

# Flutter 日志
flutter logs
```

### 3. 设备池过期

若 content/full 解密乱码，删除应用私有目录下 `files/backend/config/device_pool.json` 重启 App 即可自动重注册。

### 4. 桌面播放依赖

- **libmpv / VC++ 运行库**：media_kit 随包分发 libmpv（MSVC 构建），依赖 VC++ 2015–2022 运行库。
  安装程序会自动部署；若目标机缺失，启动时会报 libmpv 加载失败，桌面视频/听书播放不可用但其余功能不受影响。
- **宽屏布局**：导航与列宽按窗口宽度分级，拖动窗口跨断点由 `MediaQuery` 自然重建，无需额外监听。
- **界面缩放**：`services/ui_scale.dart` 保存 90/100/110/125% 档位，`widgets/ui_zoom.dart` 在 `MaterialApp.builder` 里把逻辑视口按比例缩放后用 `FittedBox` 铺回窗口；`MediaQuery.size/padding/viewInsets` 同步换算，100% 时直接返回原树。

---

## 开发计划

- [x] **Rust 原生核心**：`fanqieduanwan_core` → `fanqieduanwan_core.dll` → flutter_rust_bridge 进程内调用（替代 Go/Kotlin JNI）
- [x] 小说搜索、目录、正文、章节/滚动位置续读
- [x] 短剧目录归一化、自动连播、播放进度续看
- [x] 首页真实推荐接口（`/api/v1/recommend/homepage`）
- [x] 短剧流式播放（media_kit + CENC 解密与 HTTP Range）
- [x] 可重建的 C 短剧流式解密，编入核心（见 [C 库说明](native/README.md)）
- [x] 漫画原生阅读页、章节目录、单图重试与进度恢复；宽屏 2/3/4 页并排
- [x] 听书前台播放、目录、倍速和进度恢复
- [x] 小说章节下载/离线缓存
- [x] 发现类入口：搜索联想词与热搜、作者主页、排行榜、书评回复、章节试读预览
- [x] 整本 TXT 导出（离线缓存页每行「导出 TXT」→ 系统「下载」）
- [x] 宽屏自适应：导航分级（900/1200）、首页列宽分级、设置双列、视频键盘快捷键
- [x] 桌面交互重构：滚轮调音量、`PageUp/PageDown` 切集、切集淡出、`Ctrl+1..4` 切页、`F5/Ctrl+R` 刷新、详情页宽屏两栏
- [x] 应用内界面缩放（90/100/110/125%）
- [x] Windows 安装包（InnoSetup）与 CI 云端构建、打 tag 发布 Release
- [ ] Windows 真机验收：启动、搜索、阅读、桌面播放、宽屏布局回归
- [ ] 备份与恢复（跨设备迁移）实测
- [ ] 集成测试补强：桌面播放器降级、备份恢复合并、设备注册过期重注册
