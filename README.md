<div align="center">
  <img src="icon1.png" width="104" alt="PocketJ Launcher Icon">
  <img src="icon2.png" width="320" alt="PocketJ Launcher Banner">

  # PocketJ Launcher

  **掌上 Java，不只是“能启动”。**  
  A modern Minecraft: Java Edition launcher built for iPhone and iPad.

  [![Version](https://img.shields.io/badge/version-v1.6-20c66b?style=for-the-badge)](../../releases)
  ![Platform](https://img.shields.io/badge/iOS%20%7C%20iPadOS-14--27-111111?style=for-the-badge&logo=apple&logoColor=white)
  [![License](https://img.shields.io/badge/license-GPL--3.0-7c5cff?style=for-the-badge)](LICENSE)
  ![Languages](https://img.shields.io/badge/UI-简体中文%20%7C%20English-28a8ea?style=for-the-badge)

  [简体中文](#-简体中文) · [English](#-english) · [下载 Releases](../../releases) · [反馈问题](../../issues/new/choose)
</div>

> **PocketJ Launcher v1.6**
>
> 本版加入 iOS 27+ 本机配对，保留电脑配对与文件导入；精简 JIT 界面，
> 实时更新 LocalDevVPN 连接状态，并补齐配对成功页、完成通知与触感反馈。
> 同时完善离线中文模组搜索、实例版本固定、设置布局和首页运行 JAR 入口。
>
> This release adds on-device pairing on iOS 27+, retains computer pairing and
> file import, simplifies JIT setup, and refreshes LocalDevVPN reachability live.
> It also improves pairing feedback, offline Chinese mod search, pinned instance
> versions, settings layouts, and the home-page Run JAR entry.
>
> 完整更新与安装包说明见 [v1.6 更新说明 / Release notes](RELEASE_NOTES.md)。

> [!IMPORTANT]
> PocketJ Launcher 是社区维护的开源项目，并非 Mojang Studios 或 Microsoft 的官方产品。Minecraft 是 Microsoft Corporation 的商标。

---

# 🇨🇳 简体中文

> [!TIP]
> ## 🧰 两种配对方式，按系统选择
> **iOS / iPadOS 27 及以上：** 打开「设置 → 运行环境 → JIT → 配对文件 → 本机配对」，按页面引导在系统设置输入通知中的配对码，无需电脑。成功后会显示完成页并发送完成反馈。
>
> **电脑配对继续保留：** 在「配对文件」中点击「从电脑导入」打开配对工具发布页；用 macOS、Windows 或 Linux 工具生成文件后，选择「导入已有文件」，也可由工具直接写入 PocketJ。
>
> [⬇️ 下载 PocketJ 配对工具 v1.0][pairing-tool-release] · [查看全部 Releases][pairing-tool-releases]
>
> 两种方式获得的文件都用于后续 JIT 连接；完成配对后仍需连接 LocalDevVPN。

## 为什么选择 PocketJ？

很多移动端 Java 启动器止步于“把游戏打开”。PocketJ 更想把桌面启动器的完整体验带到 iOS：**在一个原生应用里完成 JIT、实例、Java、模组、整合包、账户、控制与诊断。**

同时，PocketJ 不只关注功能完整性，也持续针对 iOS 环境优化启动流程、资源加载和渲染体验。相比早期移动端 Java 启动方案，PocketJ 在保持兼容性的基础上，对启动链路、运行效率和设备适配进行了大量优化，目标是在 iPhone 和 iPad 上提供更快速、更稳定、更接近桌面体验的 Minecraft Java 运行效果。

它基于 GPL-3.0 项目 [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) 持续开发，并继承了 [PojavLauncher](https://github.com/PojavLauncherTeam) 与 Boardwalk 生态的工作。v1.6 延续既有 Minecraft 版本兼容基础，重点完善免电脑配对、JIT 连接体验、中文搜索与原生界面。

### 📸 查看真实运行截图

想先看看 PocketJ 在不同设备上的实际效果？进入 [截图画廊](Example/README.md)，可按 iOS 27、iPadOS 18、iPhone X + iOS 14 以及 Forge 测试分类浏览；所有缩略图均可点击查看原图。

[![Screenshots](https://img.shields.io/badge/截图画廊-查看设备实测-20c66b?style=for-the-badge&logo=apple&logoColor=white)](Example/README.md)

## ✨ 别人缺少的，PocketJ 正在做

| PocketJ 能力 | 你可以做什么 |
|---|---|
| ⚡ **内置 JIT 工作流** | iOS 27+ 可在本机配对，也可导入电脑生成的文件；实时检查连接状态，再为 PocketJ 开启 JIT |
| 🧩 **iOS 原生资源中心** | 浏览 Modrinth 与 CurseForge，按实例版本和加载器筛选模组、整合包、光影包、材质包与数据包 |
| 🎛️ **实例级模组管理** | 查看已安装模组、启用/停用、检查更新、选择具体版本；不兼容项目会被明确标记，但选择权仍交给玩家 |
| 📦 **统一实例与整合包入口** | 新建实例、导入 ZIP、浏览在线整合包都集中在同一个 `+` 菜单；每个整合包创建独立实例，避免覆盖当前游戏 |
| ☕ **智能 Java 分配** | 内置并管理 Java 8、17、21、25，根据 Minecraft 世代自动选择，同时允许高级用户逐实例覆盖 |
| 🕰️ **经典与远古版本兼容** | 为旧版 Java、内存与启动参数提供独立兼容路径；兼容开关可随时关闭，避免影响现代版本 |
| 🌍 **Minecraft 全世代支持** | 从远古 Alpha / Beta、经典正式版到现代 26.x，由 Java 8 / 17 / 21 / 25 和分代渲染路径自动匹配 |
| 🎨 **自定义启动器背景** | 选择任意图片，按当前 iPhone / iPad 屏幕比例裁切，并独立调整背景透明度 |
| ⏯️ **可恢复下载队列** | 下载暂停、继续、失败重试与本地文件复用；有效文件不会无意义地重复下载 |
| 🎮 **真正为触屏设计** | 原版控制编辑器、触控键位、手柄映射分区，以及可即时切换的灵敏八方向移动逻辑 |
| 👤 **正版与离线账户共存** | Microsoft 与离线账户使用独立身份保存；同名账户不再互相覆盖，并支持 Minecraft 皮肤头像缓存 |
| 🧾 **不再黑屏猜错** | 下载、JIT、加载器安装和游戏启动均有可见状态；日志可查看、导出并用于 Issue 定位 |

<details>
<summary><strong>⚡ 内置 JIT 是怎样工作的？</strong></summary>

- iOS / iPadOS 27 及以上可在手机或平板本机完成配对；配对码通过通知显示，保存成功后有明确完成页。
- 电脑配对工具、已有文件导入、导出和删除均保留，集中在「配对文件」页面。
- JIT 页面在前台可见时每秒检测一次连接，返回应用立即刷新；点击 LocalDevVPN 优先打开 App，未安装时转到 App Store。
- iOS 26 及以上使用随包的独立 JIT Helper；17.4–25 的现有入口交给独立 StikDebug，14–17.3 需使用其他受支持的 JIT 方式。
- 配对成功不等于 JIT 已开启；完成配对后连接 LocalDevVPN，再点击「开启 JIT」。
- JIT、扩展虚拟地址空间和更高内存限制是不同能力，最终可用性取决于系统、签名和 entitlement。

</details>

<details>
<summary><strong>🧩 模组工作流包含什么？</strong></summary>

- 内置 Modrinth 与 CurseForge 搜索、项目图标、版本列表与兼容性筛选。
- 模组、整合包、光影包、材质包和数据包共用原生在线浏览与下载流程。
- 自动读取当前实例的 Minecraft 版本与 Fabric / Forge / NeoForge / Quilt 元数据。
- 内置离线中文名称与别名索引，支持简繁体匹配，无需手动导入 CSV；未知词保留原始查询。
- 对已安装 `.jar` 使用可逆的 `.disabled` 方式开关，不删除原文件。
- 新建和编辑实例共用统一加载器模型，Minecraft 版本与 Loader 版本不再混为一谈。

</details>

## ✅ Minecraft 兼容基线

以下兼容范围沿用 v1.4 / v1.5，不作为 v1.6 新增亮点。不同游戏版本、加载器、模组和设备组合仍应以实际运行结果为准。

| 组合 | 当前定位 |
|---|---|
| **Minecraft 26.x 与现代版本** | 🟢 接入新版 LWJGL / SDL 输入兼容与对应渲染链；NeoForge 版本列表匹配至 26.3 |
| **Minecraft 1.x 经典正式版** | 🟢 按版本世代自动匹配 Java Runtime 和渲染器 |
| **Alpha / Beta 与远古版本** | 🟢 具备独立旧版内存兼容路径，不干扰现代版本 |
| **Fabric / Forge / NeoForge / Quilt** | 🟢 统一 Minecraft 版本和 Loader 版本模型，依据实例筛选对应加载器版本 |

> [!TIP]
> 初次体验仍建议从稳定正式版开始。极旧或加载器组合仍受上游资源和设备内存影响，出现问题时请附上 `latestlog.txt`。

## 📱 系统要求

- iOS / iPadOS 14.0–27
- 64 位 arm64 iPhone 或 iPad
- 现代 Minecraft 通常需要 JIT、足够的可用内存和正确的签名权限
- 新版 Minecraft 与大型整合包推荐使用内存更充足的设备

## ⬇️ 安装

前往 [Releases](../../releases) 下载：

| 文件 | 用途 |
|---|---|
| `PocketJLauncher-v1.6-iOS.ipa` | AltStore、SideStore 及兼容的 IPA 侧载方式，由安装工具按需签名 |
| `PocketJLauncher-v1.6-iOS-TrollStore.tipa` | 适用于受支持的 TrollStore 环境 |
| `SHA256SUMS.txt` | 校验下载文件是否完整、是否与发布产物一致 |

自动检查只识别 PocketJ Launcher 稳定版，配对工具版本不会混入；“关于”中的手动检查会实时查询，并遵循跳过/延后例外规则。

> [!WARNING]
> 普通签名证书不一定包含 Java 所需的 JIT、扩展虚拟地址空间和更高内存 entitlement。安装成功不等于这些能力均已生效。

## 🚀 五步开始

1. 安装 PocketJ Launcher。
2. 添加 Microsoft 账户或离线账户。
3. 在“游戏”中创建实例，推荐选择 `1.21.11 + Fabric`。
4. 在“设置 → 运行环境 → JIT”完成配置并开启 JIT。
5. 回到“启动”，等待资源完成后开始游戏。

## 🧑‍💻 从源码构建

### 准备

- macOS 与 Xcode
- Xcode Command Line Tools
- Homebrew 中的 `gmake`、`cmake`、`wget`、`ldid`
- Java 8 Boot JDK（仅用于编译启动器；不等于 Minecraft 实例使用的 Java 版本）
- Rust 工具链及已安装的 `aarch64-apple-ios` 目标，用于本机配对模块
- 完整的共享依赖目录 `iOS版本/SharedDependencies/PocketJ/`；其中 `Vendor/PocketJPairing` 复用配对工具 v1.1 的 idevice 源码入口，单独移动 v1.6 时需同时保留其相对链接目标
- 配对模块 `Cargo.lock` 对应的依赖缓存；构建采用离线锁定模式，不自动安装或更新工具链

### Xcode

1. 打开 `PocketJLauncher.xcodeproj`。
2. 选择 **PocketJ Launcher** scheme。
3. 在 Signing & Capabilities 中选择自己的开发团队。
4. 连接 iPhone / iPad，Clean Build Folder 后运行。

### Makefile

下面只构建原生 / Java 载荷；完整 JIT Helper、本机配对模块与整包请使用上述 Xcode 入口。

```bash
gmake payload PLATFORM=2 BOOTJDK="/path/to/jdk8/bin"
```

<details>
<summary><strong>🗂️ 仓库结构</strong></summary>

```text
PocketJLauncher.xcodeproj   Xcode 真机构建入口
XcodeRunner/                App、JIT Helper 与构建包装逻辑
Natives/                    iOS UI、实例、模组、JIT 与原生运行层
JavaApp/                    Java 启动器及 LWJGL 兼容代码
Vendor/StikJIT/             内置 JIT 相关组件
../SharedDependencies/      跨版本共享的运行时、工具与配对模块
RELEASE_NOTES.md            v1.6 更新与交付说明
THIRD_PARTY_LICENSES/       第三方许可证
Makefile                    原生、Java、Runtime 与打包流程
NOTICE.md                   修改声明及上游归属
```

</details>

## 🐛 反馈与贡献

提交 Issue 时请尽量包含：

- 设备型号与 iOS / iPadOS 版本
- PocketJ 版本
- Minecraft、Java、模组加载器及其版本
- 完整复现步骤
- `latestlog.txt`（请先移除账户令牌、证书等隐私数据）

[![Open an Issue](https://img.shields.io/badge/GitHub-提交问题-181717?style=for-the-badge&logo=github)](../../issues/new/choose)
[![Telegram](https://img.shields.io/badge/Telegram-加入交流群-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+wqBdm5YDqR8yYTNl)
[![QQ Group](https://img.shields.io/badge/QQ群-1062592009-12B7F5?style=for-the-badge&logo=tencentqq&logoColor=white)](https://qm.qq.com/)

## 👨‍🚀 维护者

**Erico** · [@EricoEC](https://github.com/EricoEC)  
项目主页：[github.com/EricoEC/PocketJLauncher](https://github.com/EricoEC/PocketJLauncher)

## 📜 开源协议与致谢

PocketJ Launcher 主项目依据 **GNU GPL v3.0** 发布。项目包含源自 StikDebug 的修改代码，其许可证及归属见 [NOTICE.md](NOTICE.md) 与 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/)。分发修改版本或二进制时，请同时履行适用的源代码、版权、许可证及无担保声明义务。

感谢 PojavLauncher 上游项目的贡献。其他第三方组件的版权、许可证与必要归属信息按各自要求列于 [NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/)；上游代码版权仍归各自作者所有。

Copyright © 2026 Erico.

<p align="right"><a href="#pocketj-launcher">⬆️ 返回顶部</a></p>

---

# 🇬🇧🇺🇸 English

> [!TIP]
> ## 🧰 Choose on-device or computer pairing
> **iOS / iPadOS 27 and later:** Open **Settings → Runtime → JIT → Pairing File → On-device Pairing**, then follow the guide and enter the notification's PIN in system Settings. No computer is needed. Successful saving shows a completion page and feedback.
>
> **Computer pairing remains available:** **Import from Computer** opens the pairing-tool release. Generate a file on macOS, Windows, or Linux, then choose **Import an Existing File**, or let the tool write it directly to PocketJ.
>
> [⬇️ Download PocketJ Pairing Tool v1.0][pairing-tool-release] · [Browse all Releases][pairing-tool-releases]
>
> Both methods prepare credentials for JIT. LocalDevVPN is still needed after pairing.

## Why PocketJ?

Many mobile Java launchers stop at opening the game. PocketJ aims to bring a complete desktop-launcher workflow to iOS: **JIT, instances, Java runtimes, mods, modpacks, accounts, controls, and diagnostics—all inside one native app.**

At the same time, PocketJ focuses not only on feature completeness, but also on improving the iOS Java runtime experience. Compared with earlier mobile Java launcher solutions, PocketJ introduces continuous optimizations across the launch pipeline, resource loading, rendering experience, and device adaptation, aiming to provide a faster, more stable Minecraft Java experience closer to desktop launchers on iPhone and iPad.

PocketJ is developed from the GPL-3.0 licensed [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) project and inherits substantial work from the [PojavLauncher](https://github.com/PojavLauncherTeam) and Boardwalk ecosystems. Version 1.6 retains the existing Minecraft compatibility baseline and improves computer-free pairing, JIT connections, Chinese search, and native UI layouts.

### 📸 See PocketJ running on real devices

Visit the [screenshot gallery](Example/README.md) to browse iOS 27, iPadOS 18, iPhone X + iOS 14, and Forge test galleries. Every compact preview opens its full-resolution image.

[![Screenshots](https://img.shields.io/badge/Screenshot%20Gallery-Real%20Device%20Tests-20c66b?style=for-the-badge&logo=apple&logoColor=white)](Example/README.md)

## ✨ What PocketJ brings to iOS

| PocketJ capability | What it gives you |
|---|---|
| ⚡ **Built-in JIT workflow** | Pair on-device on iOS 27+, or import a computer-generated file; inspect live connection state and enable JIT for PocketJ |
| 🧩 **Native resource center** | Browse Modrinth and CurseForge mods, modpacks, shaders, resource packs, and data packs with instance-aware filtering |
| 🎛️ **Per-instance mod management** | Inspect installed mods, enable or disable them, check updates, and choose exact versions |
| 📦 **Unified instance and modpack entry** | Create an instance, import a ZIP, or browse online modpacks from one `+` menu; modpacks are isolated instead of replacing the active instance |
| ☕ **Smart Java selection** | Manage Java 8, 17, 21, and 25; automatically match game generations while retaining per-instance overrides |
| 🕰️ **Classic-version compatibility** | A dedicated legacy path adjusts Java-era memory and startup behavior without changing the modern path |
| 🌍 **Every Minecraft generation** | Alpha, Beta, classic releases, modern releases, and 26.x use generation-aware Java and rendering paths |
| 🎨 **Custom launcher backgrounds** | Crop a photo to the current iPhone or iPad aspect ratio and control its transparency independently |
| ⏯️ **Resumable downloads** | Pause, resume, retry, and reuse valid local files instead of downloading everything again |
| 🎮 **Touch-first controls** | Original control editor, separated touch/controller mapping, and responsive eight-direction movement |
| 👤 **Microsoft and offline coexistence** | Separate account identities prevent same-name accounts from replacing each other; Minecraft avatar caching is included |
| 🧾 **Visible launch state** | JIT, downloads, loader installation, and game launch expose progress and exportable logs instead of silent black screens |

<details>
<summary><strong>⚡ How does built-in JIT work?</strong></summary>

- On iOS / iPadOS 27 and later, pair directly on the phone or tablet. The PIN is delivered through a notification, followed by a clear completion page after saving.
- Computer pairing, existing-file import, export, and deletion remain available under Pairing File.
- While the JIT page is visible in the foreground, connections are checked every second and immediately on returning to the app. The LocalDevVPN row opens its app first and falls back to the App Store.
- iOS 26 and later use the bundled independent JIT Helper. The existing iOS 17.4–25 entry hands off to independent StikDebug; iOS 14–17.3 needs another supported JIT method.
- Pairing completion does not mean JIT is enabled: connect LocalDevVPN, then tap Enable JIT.
- JIT, extended virtual address space, and increased memory limits are separate capabilities and depend on the OS, signature, and entitlements.

</details>

<details>
<summary><strong>🧩 What is included in the mod workflow?</strong></summary>

- Built-in Modrinth and CurseForge search, icons, version selection, and compatibility filters.
- One native workflow for mods, modpacks, shaders, resource packs, and data packs.
- Instance metadata detection for Minecraft and Fabric / Forge / NeoForge / Quilt.
- A bundled offline Chinese name/alias index with Simplified/Traditional matching; no manual CSV import is required, and unknown queries stay unchanged.
- Reversible `.disabled` toggles for installed JAR files.
- One loader model shared by creation and editing, keeping Minecraft versions separate from loader versions.

</details>

## ✅ Minecraft compatibility baseline

The following compatibility is carried forward from v1.4 / v1.5 and is not new in v1.6. Actual behavior still depends on the game, loader, mods, and device combination.

| Combination | Current status |
|---|---|
| **Minecraft 26.x and modern releases** | 🟢 Includes LWJGL / SDL input compatibility and the matching renderer path; NeoForge version matching includes 26.3 |
| **Classic Minecraft 1.x releases** | 🟢 Automatically selects a generation-appropriate Java runtime and renderer |
| **Alpha, Beta, and legacy releases** | 🟢 Uses an isolated legacy-memory compatibility path without changing modern versions |
| **Fabric / Forge / NeoForge / Quilt** | 🟢 Shares one Minecraft/loader version model and filters loader releases against the selected game version |

> [!TIP]
> A stable release is still the easiest first run. Very old or loader-heavy combinations remain sensitive to upstream assets and device memory; attach `latestlog.txt` when reporting an issue.

## 📱 Requirements

- iOS / iPadOS 14.0–27
- A 64-bit arm64 iPhone or iPad
- Modern Minecraft generally needs JIT, enough available memory, and appropriate signing entitlements
- Newer Minecraft releases and large modpacks benefit from newer devices

## ⬇️ Downloads

Get release assets from [Releases](../../releases):

| File | Purpose |
|---|---|
| `PocketJLauncher-v1.6-iOS.ipa` | For AltStore, SideStore, and compatible IPA sideloading methods; the installer signs it as needed |
| `PocketJLauncher-v1.6-iOS-TrollStore.tipa` | Supported TrollStore environments |
| `SHA256SUMS.txt` | Verifies release-file integrity |

Automatic checks select stable PocketJ Launcher releases and exclude pairing-tool versions. Manual checks in About query again and bypass the skip/reminder rules.

> [!WARNING]
> A signing certificate may install the app without granting JIT, extended virtual address space, or increased-memory entitlements.

## 🚀 Start in five steps

1. Install PocketJ Launcher.
2. Add a Microsoft or offline account.
3. Create an instance under Games; `1.21.11 + Fabric` is recommended.
4. Configure JIT under Settings → Runtime → JIT.
5. Return to Launch, let resources finish, and start the game.

## 🧑‍💻 Build from source

### Prerequisites

- macOS and Xcode
- Xcode Command Line Tools
- `gmake`, `cmake`, `wget`, and `ldid` from Homebrew
- A Java 8 Boot JDK for compiling the launcher; this is separate from the Java runtime selected for Minecraft
- A Rust toolchain with the `aarch64-apple-ios` target already installed
- The complete `iOS版本/SharedDependencies/PocketJ/` workspace directory; `Vendor/PocketJPairing` reuses the idevice source from pairing tool v1.1, so preserve that relative symlink target when moving v1.6
- Cached dependencies matching the pairing module's `Cargo.lock`; its build is offline and locked, without automatic toolchain installation or updates

### Xcode

1. Open `PocketJLauncher.xcodeproj`.
2. Select the **PocketJ Launcher** scheme.
3. Choose your development team under Signing & Capabilities.
4. Connect an iPhone or iPad, Clean Build Folder, and run.

### Makefile

This builds the native / Java payload only. Use Xcode above for the complete app, independent JIT Helper, and on-device pairing module.

```bash
gmake payload PLATFORM=2 BOOTJDK="/path/to/jdk8/bin"
```

<details>
<summary><strong>🗂️ Repository layout</strong></summary>

```text
PocketJLauncher.xcodeproj   Xcode device-build entry point
XcodeRunner/                App, JIT Helper, and build-wrapper logic
Natives/                    iOS UI, instances, mods, JIT, and native runtime
JavaApp/                    Java launcher and LWJGL compatibility code
Vendor/StikJIT/             Built-in JIT components
../SharedDependencies/      Shared runtimes, tools, and pairing module
RELEASE_NOTES.md            v1.6 changes and delivery notes
THIRD_PARTY_LICENSES/       Third-party license texts
Makefile                    Native, Java, runtime, and packaging pipeline
NOTICE.md                   Modification notice and upstream attribution
```

</details>

## 🐛 Issues and contributions

Please include the following in a useful bug report:

- Device and iOS / iPadOS version
- PocketJ version
- Minecraft, Java, mod loader, and loader version
- Complete reproduction steps
- `latestlog.txt`, after removing tokens, certificates, and private data

[![Open an Issue](https://img.shields.io/badge/GitHub-Open%20an%20Issue-181717?style=for-the-badge&logo=github)](../../issues/new/choose)
[![Telegram](https://img.shields.io/badge/Telegram-Join%20the%20community-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/+wqBdm5YDqR8yYTNl)
[![QQ Group](https://img.shields.io/badge/QQ%20Group-1062592009-12B7F5?style=for-the-badge&logo=tencentqq&logoColor=white)](https://qm.qq.com/)

## 👨‍🚀 Maintainer

**Erico** · [@EricoEC](https://github.com/EricoEC)  
Project home: [github.com/EricoEC/PocketJLauncher](https://github.com/EricoEC/PocketJLauncher)

## 📜 License and acknowledgements

The PocketJ Launcher main project is distributed under **GNU GPL v3.0**. It includes modified StikDebug-derived code; see [NOTICE.md](NOTICE.md) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/) for applicable attribution and license texts. Binary and modified-source distribution must preserve all applicable source, copyright, license, and warranty-notice obligations.

Thanks to the PojavLauncher upstream project. Copyright, license, and required attribution notices for other third-party components are recorded in [NOTICE.md](NOTICE.md) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/); upstream code remains the property of its respective authors.

Copyright © 2026 Erico.

<p align="right"><a href="#pocketj-launcher">⬆️ Back to top</a></p>

[pairing-tool-release]: ../../releases/tag/pairing-tool-v1.0
[pairing-tool-releases]: ../../releases
