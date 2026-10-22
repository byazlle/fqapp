<p align="center">
  <img src="assets/images/app_logo.webp" width="120" height="120" alt="番茄端碗 FanqieDuanwan Logo">
</p>

<h1 align="center">番茄端碗 · FanqieDuanwan</h1>

<p align="center">
  <strong>内容聚合客户端 · Windows 桌面版</strong><br>
  小说 · 短剧 · 漫剧 · 漫画 · 听书，签名 / 解密 / 缓存全部在本机完成
</p>

<p align="center">
  <a href="#-功能一览">功能一览</a> ·
  <a href="#-下载与安装">下载与安装</a> ·
  <a href="#-快速上手">快速上手</a> ·
  <a href="#-常见问题">常见问题</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="#-支持作者">支持作者</a> ·
  <a href="DEVELOPMENT.md">开发者文档</a>
</p>

<p align="center">
  <a href="https://github.com/byazlle/winFQAPP/releases/latest">
    <img alt="Release" src="https://img.shields.io/github/v/release/byazlle/winFQAPP?color=E8342A&label=Release&logo=github">
  </a>
  &nbsp;
  <a href="https://github.com/byazlle/winFQAPP/releases">
    <img alt="Downloads" src="https://img.shields.io/github/downloads/byazlle/winFQAPP/total?color=FF9F1C&label=Downloads&logo=github">
  </a>
  &nbsp;
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Windows%2010%2F11%20x64-0078D4?logo=windows&logoColor=white">
  &nbsp;
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-GPL--3.0-blue">
  </a>
  &nbsp;
  <a href="https://github.com/byazlle/winFQAPP/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/byazlle/winFQAPP?style=social">
  </a>
</p>

<p align="center">
  <a href="https://github.com/byazlle/winFQAPP/releases/latest">
    <img alt="下载安装包" height="44" src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-Windows%20%E5%AE%89%E8%A3%85%E5%8C%85-0078D4?style=for-the-badge&logo=windows&logoColor=white">
  </a>
</p>

> **当前版本：`v1.3.2`（构建号 137）** —— 桌面交互重构：滚轮调音量、键盘切集、宽屏详情两栏与应用内界面缩放。
> `0.9.x`、`1.0.0`、`1.1.0`、`1.2.0`、`1.2.1`、`1.3.0` 与 `1.3.1` 为历史版本，完整变更见 [CHANGELOG.md](CHANGELOG.md)。

> **关于更名**：本项目先后使用过 `fqapp` 与 `流光 / Liuguang`，自 `v1.2.0` 起定名
> **番茄端碗（FanqieDuanwan）**——取意「内容来自番茄小说与番茄视频，端到碗里给你看」。
> 安装包、可执行文件、安装目录、快捷方式与界面标识均已切换；升级时首次启动会自动把
> `%APPDATA%\byazlle\Liuguang` 或 `%APPDATA%\fqapp` 的旧数据搬到新目录（`%APPDATA%\byazlle\FanqieDuanwan`），书架、历史与缓存不丢。
> 搬迁每个旧目录只做一次并留标记，卸载后重装不会再把已清空的本地数据「搬回来」。

> ⚠️ **免责声明**：本项目仅供学习与研究交流，不内置、不分发任何内容资源；在线内容均来自第三方公开接口，版权归原权利方所有。本项目与内容提供方无关联，未获其授权；使用产生的一切后果由使用者自行承担，如有侵权请联系删除。

---

## 📖 功能一览

| 功能 | 说明 |
|---|---|
| 📖 小说阅读 | 图文正文与插图、左右分页或上下滚动、排版与字体导入、亮度调节、段评、离线缓存 |
| 🎬 短剧 / 漫剧 | 自动连播、倍速、上下集与快进快退、全屏方向自适应、进度续看；键盘切集、滚轮调音量 |
| 🖼 漫画 | 竖向连续阅读、章节目录、单图重试、点击放大、阅读位置恢复；宽屏支持 2/3/4 页并排 |
| 🎧 听书 | 智能朗读与真人讲书、边听边读字幕、关联作品、定时关闭、倍速、自动下一章、进度续听 |
| 🔍 搜索与发现 | 关键词 / 作品 ID 搜索、搜索联想词与热搜、排行榜、作者主页、书评 |
| 📋 详情 | 封面、分类、完结状态、字数、评分、标签、简介、作者、目录预览、书评；宽屏自动切为两栏 |
| 🕘 历史与书架 | 阅读 / 播放进度自动记录，续读续看；可按条目删除或整体清空 |
| ⬇️ 下载 | 整本缓存、批量缓存后续章节，下载内容不受自动清理影响 |
| 💾 数据与缓存 | 章节缓存与图片缓存分开统计占用、可分别清理；数据目录可整体迁移到其他磁盘 |

## ⬇️ 下载与安装

### 设备要求

- **Windows 10 / 11（64 位，x64）**。
- 需要网络：在线内容实时从上游获取，App 本身不内置任何内容。
- **安装需要管理员权限**：安装程序会把 VC++ 2015–2022 运行库部署到系统目录（桌面播放组件 libmpv 依赖它）。
- 安装包**未做代码签名**，首次运行时 Windows SmartScreen 会提示，选择「更多信息 → 仍要运行」即可。
- 本版本仅支持 Windows 桌面端，**不提供 Android / iOS 包**。

### 获取安装包

**推荐：[GitHub Releases](https://github.com/byazlle/winFQAPP/releases/latest)** —— 下载最新发布版的
`fanqieduanwan-setup-x64.exe`；打 tag 发布的版本同时附带 `SHA256SUMS.txt`，可对照 Release 说明中的 SHA256 自行核对：

```powershell
Get-FileHash .\fanqieduanwan-setup-x64.exe -Algorithm SHA256
```

其他方式：

1. **GitHub Actions 云端构建**：打开仓库的 [Actions → Build Windows (cloud)](https://github.com/byazlle/winFQAPP/actions/workflows/build-windows.yml)，点击 **Run workflow** 运行一次构建；成功后在本次运行的 **Artifacts** 中下载 `fanqieduanwan-windows-setup`，解压得到 `fanqieduanwan-setup-x64.exe`（产物保留 14 天，长期留存请用 Releases）。
2. **本地构建**：需要 Flutter / Rust / Visual Studio (MSVC) / Inno Setup，步骤见 [DEVELOPMENT.md](DEVELOPMENT.md)。

### 安装与首次启动

1. 双击 `fanqieduanwan-setup-x64.exe` 按向导安装（会自动部署 VC++ 运行库），从开始菜单或桌面快捷方式启动。
2. 首次启动时 App 自动完成初始化：部署运行资源 → 启动本地核心并注册设备 → 健康检查通过后进入主界面。首次请保持联网。
3. 之后即可随时离线打开 App，阅读已缓存的内容。

### 升级与卸载

- **升级**：同一发布渠道的安装包可直接覆盖升级（安装包都未签名，覆盖安装不涉及签名校验）；阅读历史、收藏与缓存会被保留。
- **卸载**：卸载程序会删除默认数据目录 `%APPDATA%\byazlle\FanqieDuanwan`，并一并清掉 fqapp / Liuguang 时期遗留的旧目录；阅读历史、收藏与缓存随之清除。
- **迁移过数据目录时**：卸载程序**不会**清理自定义目录，需要手动删除；该目录中的 `fanqieduanwan-data.txt` 写有这条说明。

## 🚀 快速上手

### 找内容

- **首页**：推荐流混排小说、短剧、漫剧、漫画、听书；用顶栏刷新按钮或 `F5` / `Ctrl+R` 刷新（桌面端不使用下拉刷新），推荐不可用时自动回退分类搜索。
- **搜索**：支持关键词与作品 ID 两种方式——输入 15–20 位纯数字自动按 ID 查找，也可用 `id:作品ID` 显式查询；结果按综合、小说、短剧、漫剧、漫画、听书分栏展示。
- **宽屏布局**：窗口 ≥900 时导航从底部药丸切换为左侧悬浮栏，≥1200 展开为「图标 + 文字」并可收起为纯图标列；首页内容列宽随窗口分级放开（840/920/1080）。窄窗口仍是紧凑布局。
- **详情两栏**：内容区 ≥1080 时详情页左栏放封面、标题、作者、阅读数据与标签，右栏放简介、目录与评论。
- **界面缩放**：设置 → 外观 → 界面缩放，可选 90% / 100% / 110% / 125%，整体文字与布局一起缩放（类似浏览器缩放），高分屏或远距离观看更舒服。
- **页面切换**：`Ctrl+1`–`Ctrl+4` 直达首页 / 短剧 / 书架 / 我的。

### 读小说

- 左右分页与上下滚动两种翻页方式；正文两端对齐、首行缩进。阅读信息默认简洁（底部时间与全书进度），排版设置中可切换详细信息或关闭。
- 分页翻过本章最后一页直接进入下一章正文，反向翻页进入上一章末页；有评论数据时，可从阅读菜单查看本章评论。
- 排版面板实时调整字号、字重、字距、行距、段距、边距与阅读背景（四种主题），设置自动保存。
- 支持导入自定义字体（TTF / OTF / TTC，单文件不超过 32 MB）。
- 有段评的段落会在行内显示评论数气泡，点击查看该段评论。
- 点击正文中央呼出菜单：目录（可搜索、倒序、定位当前章）、排版、缓存。

### 看短剧 / 漫剧

- 自动连播：一集播完自动下一集；支持选集、上下集、快进快退 10 秒和全屏。
- 横屏控制条提供：上一集 / 播放暂停 / 重播 10 秒 / 前进 10 秒 / 下一集 / 选集。
- 0.75–2 倍速可保存；按住画面临时 2 倍速。
- 全屏方向按视频比例自适应（横屏剧集横屏、竖屏剧集竖屏），也可锁定方向。
- 播放进度自动记录，随时续看。
- **桌面键盘快捷键**：上下方向键长按连续步进、空格播放 / 暂停、倍速记忆、音量调节（每项均保留可点击控件）。
- **切集与滚轮**：`PageUp` / `[` 上一集，`PageDown` / `]` 下一集；鼠标滚轮在画面上调节音量（约一格 5%），不再触发上下翻页。换集时有 200ms 淡出过渡。

### 听书

- 智能朗读与真人讲书两种模式，多个音色可切换，切换时保留播放位置。
- 智能朗读的「边听边读」打开正文阅读器；开启阅读设置中的听书跟随翻页后，按播放进度估算翻页并跟随章节。真人录音保留同步字幕，当前句高亮。
- 返回或浏览其他页面继续听书，底部控制条可以回到听书页、暂停或主动关闭。重开同一作品复用当前播放；手动选章节或「从本段听」按指定位置开始。
- 切到其他窗口或最小化后仍可继续播放（可在设置中开关）。
- 定时关闭（15/30/60 分钟）、倍速、上下章、进度拖动与 ±15 秒快退快进。
- 播放进度与音色选择自动保存，重新进入续听。

### 看漫画

- 竖向连续阅读，按章节切换；图片按需加载，单张失败可重试，点图可放大。
- 宽屏支持 2/3/4 页并排（窄窗口收敛为单页）；用「图片序号 + 图片内位置」记录进度，图片加载改变高度后仍保持续读位置。

### 缓存与离线

- 详情页「下载」一键缓存整本（从续读位置起，进度显示在底栏）；阅读器「缓存」面板可批量下载后续 20/50/100 章。
- 自动缓存有上限（**500 章 / 80 MB**，超出后清理最久未读的章节）；「下载」缓存的内容不受此限制，一直保留到手动删除。
- 图片缓存另有限额（**2000 张 / 256 MB**），超出后按最久未用清理。
- 书架页右上角「离线缓存」可直接打开已缓存书籍，不依赖网络。
- 设置 → 数据 → 章节缓存：查看占用、删除单本或清空全部。

### 数据目录

- 默认数据目录为 `%APPDATA%\byazlle\FanqieDuanwan`（Hive 数据库、阅读历史、收藏与缓存）。
- 设置 → 数据 → **缓存目录**：可把数据整体迁移到其他磁盘。迁移流程是「关闭数据库 → 复制 → 校验文件数与字节数 → 原子移动」，任一步失败都不会写覆盖值、也不会删除原数据，完成后自动重启生效。
- 迁移后图片缓存也跟随新目录，不会在系统盘留下残余。

## ❓ 常见问题

**Q：启动时一直停在初始化 / 健康检查失败？**
首次启动需要联网完成设备注册，请检查网络后重试；运行状态可在「我的 → 服务状态」查看。

**Q：正文显示乱码 / 视频解密失败？**
多为设备注册过期：清除应用数据后重新打开，App 会自动重新注册设备（注意：清除应用数据会同时清除阅读历史与缓存）。

**Q：搜索、详情或播放突然失败？**
内容全部来自上游接口，上游调整或网络波动都会临时影响，可稍后重试。本项目没有自己的服务器，无法绕过上游的临时变更。

**Q：视频能打开但不出画面？**
桌面播放依赖安装包随附的 libmpv 与 VC++ 运行库：请先用官方安装包重新安装 / 修复一次；仍失败时，播放前的预检会把原因区分为「组件缺失」「流 401/502」或「网络异常」。

**Q：下载的内容保存在哪？**
保存在应用私有目录 `%APPDATA%\byazlle\FanqieDuanwan`（或你迁移后的自定义目录），不进入相册等公共空间；在应用内「设置 → 数据 → 章节缓存」管理。

**Q：换电脑怎样迁移收藏和进度？**
先退出阅读或暂停播放，在「设置 → 数据 → 备份与恢复」导出 JSON 文件，传到新电脑后在同一页面选择文件，核对预览并确认合并。支持在线作品的收藏、阅读 / 播放进度和已看剧集；已有收藏和进度保留本机记录，已看剧集取并集，可重复导入。文件不包含本地 TXT/EPUB 书籍及其进度、下载缓存、阅读时长、划线和应用设置；本地书籍请另行保留原文件。暂不提供 WebDAV 同步。

**Q：卸载后数据还在吗？**
默认数据目录会随卸载删除；如果你迁移过数据目录，卸载程序不会清理自定义目录，需要手动删除（目录中的 `fanqieduanwan-data.txt` 有说明）。

**Q：安装或运行时被 SmartScreen / 杀毒软件拦截？**
安装包没有购买代码签名证书，属于正常现象，可按「更多信息 → 仍要运行」。若杀软误报，请把安装目录加入白名单后重试。

**Q：需要登录或付费吗？**
不需要。App 没有登录、支付等任何账号功能。

**Q：有 Android / iOS 版吗？**
当前仅提供 **Windows 桌面版（x64）**；仓库已移除 Android 构建目标，历史版本中的 APK 仅为当时构建产物留存。

## 💖 支持作者

如果这个项目对你有帮助，欢迎在爱发电支持我；也欢迎给项目点一个 ⭐ Star。

[![Afdian](https://img.shields.io/badge/Afdian-Sponsor-946ce6?style=social&logo=afdian)](https://afdian.com/a/ch6vip)

应用内的同一入口在「设置 → 关于 → 支持作者」。

## 🙏 致谢

Thanks to the [LINUX DO](https://linux.do/) community for its support and feedback.

感谢 [LINUX DO](https://linux.do/) 社区的支持与反馈。

## 📄 许可与免责声明

本项目代码以 [GPL-3.0](LICENSE) 协议开源，Copyright (C) 2026 ch6vip。

本项目仅供学习与研究交流，不内置、不分发任何内容资源；在线内容均来自第三方公开接口，版权归原权利方所有。本项目与内容提供方无关联，未获其授权；使用产生的一切后果由使用者自行承担，如有侵权请联系删除。请遵守相关法律法规，仅限个人学习研究使用。

## ⭐ Star History

<a href="https://www.star-history.com/?repos=byazlle%2FwinFQAPP&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=byazlle/winFQAPP&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=byazlle/winFQAPP&type=date&theme=light&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=byazlle/winFQAPP&type=date&legend=top-left" />
 </picture>
</a>

---

## 开发者

架构、构建、API 对接、调试与开发计划等开发向文档见 **[DEVELOPMENT.md](DEVELOPMENT.md)**；构建与维护脚本说明见 [scripts/README.md](scripts/README.md)；版本变更见 [CHANGELOG.md](CHANGELOG.md)。
