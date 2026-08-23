<div align="center">
  <img src="icon1.png" width="104" alt="PocketJ Launcher Icon">
  <img src="icon2.png" width="320" alt="PocketJ Launcher Banner">

  # PocketJ Launcher

  **掌上 Java，不只是“能启动”。**  
  A modern Minecraft: Java Edition launcher built for iPhone and iPad.

  [![Version](https://img.shields.io/badge/version-v1.2-20c66b?style=for-the-badge)](../../releases)
  ![Platform](https://img.shields.io/badge/iOS%20%7C%20iPadOS-14--27-111111?style=for-the-badge&logo=apple&logoColor=white)
  [![License](https://img.shields.io/badge/license-GPL--3.0-7c5cff?style=for-the-badge)](LICENSE)
  ![Languages](https://img.shields.io/badge/UI-简体中文%20%7C%20English-28a8ea?style=for-the-badge)

  [简体中文](#-简体中文) · [English](#-english) · [下载 Releases](../../releases) · [反馈问题](../../issues/new/choose)
</div>

> [!IMPORTANT]
> PocketJ Launcher 是社区维护的开源项目，并非 Mojang Studios 或 Microsoft 的官方产品。Minecraft 是 Microsoft Corporation 的商标。

---

# 🇨🇳 简体中文

## 为什么是 PocketJ？

很多移动端 Java 启动器止步于“把游戏打开”。PocketJ 更想把桌面启动器的完整体验带到 iOS：**在一个原生应用里完成 JIT、实例、Java、模组、整合包、账户、控制与诊断。**

同时，PocketJ 不只关注功能完整性，也持续针对 iOS 环境优化启动流程、资源加载和渲染体验。相比早期移动端 Java 启动方案，PocketJ 在保持兼容性的基础上，对启动链路、运行效率和设备适配进行了大量优化，目标是在 iPhone 和 iPad 上提供更快速、更稳定、更接近桌面体验的 Minecraft Java 运行效果。

它基于 GPL-3.0 项目 [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) 持续开发，并继承了 [PojavLauncher](https://github.com/PojavLauncherTeam) 与 Boardwalk 生态的工作。v1.2 在保留成熟 JVM 与启动内核的基础上，加入了 PocketJ 自己的 iOS 工作流。

### 📸 查看真实运行截图

想先看看 PocketJ 在不同设备上的实际效果？进入 [截图画廊](Example/README.md)，可按 iOS 27、iPadOS 18、iPhone X + iOS 14 以及 Forge 测试分类浏览；所有缩略图均可点击查看原图。

[![Screenshots](https://img.shields.io/badge/截图画廊-查看设备实测-20c66b?style=for-the-badge&logo=apple&logoColor=white)](Example/README.md)

## ✨ 别人缺少的，PocketJ 正在做

| PocketJ 能力 | 你可以做什么 |
|---|---|
| ⚡ **内置 JIT 工作流** | 在启动器内导入本机配对文件、检查状态并为 PocketJ 自身开启 JIT；就绪后可从“开始游戏”直接衔接启动 |
| 🧩 **iOS 原生模组中心** | 直接浏览和搜索 Modrinth；按实例的 Minecraft 版本与加载器筛选结果，并显示项目图标和兼容状态 |
| 🎛️ **实例级模组管理** | 查看已安装模组、启用/停用、检查更新、选择具体版本；不兼容项目会被明确标记，但选择权仍交给玩家 |
| 📦 **统一实例与整合包入口** | 新建实例、导入 ZIP、浏览在线整合包都集中在同一个 `+` 菜单；每个整合包创建独立实例，避免覆盖当前游戏 |
| ☕ **智能 Java 分配** | 内置并管理 Java 8、17、21、25，根据 Minecraft 世代自动选择，同时允许高级用户逐实例覆盖 |
| 🕰️ **经典与远古版本兼容** | 为旧版 Java、内存与启动参数提供独立兼容路径；兼容开关可随时关闭，避免影响现代版本 |
| ⏯️ **可恢复下载队列** | 下载暂停、继续、失败重试与本地文件复用；有效文件不会无意义地重复下载 |
| 🎮 **真正为触屏设计** | 原版控制编辑器、触控键位、手柄映射分区，以及可即时切换的灵敏八方向移动逻辑 |
| 👤 **正版与离线账户共存** | Microsoft 与离线账户使用独立身份保存；同名账户不再互相覆盖，并支持 Minecraft 皮肤头像缓存 |
| 🧾 **不再黑屏猜错** | 下载、JIT、加载器安装和游戏启动均有可见状态；日志可查看、导出并用于 Issue 定位 |

<details>
<summary><strong>⚡ 内置 JIT 是怎样工作的？</strong></summary>

- iOS / iPadOS 17.4 及以上可在 PocketJ 内导入本机 `.plist` 或 `.mobiledevicepairing` 配对文件。
- 启动 LocalDevVPN 后，可以在 PocketJ 的运行环境页面直接开启 JIT。
- “等待配置 / 就绪 / 已启动 / 不可用”状态会明确显示，不再只给出模糊的可用提示。
- 从首页启动时，PocketJ 可先完成 JIT，再继续启动 Minecraft。
- JIT、扩展虚拟地址空间和更高内存限制是三种不同能力；最终可用性仍取决于系统、签名和 entitlement。

</details>

<details>
<summary><strong>🧩 模组工作流包含什么？</strong></summary>

- 内置 Modrinth 搜索、项目图标、版本列表与兼容性筛选。
- 可选的 CurseForge 数据源支持；自行构建时需按其 API 条款配置密钥。
- 自动读取当前实例的 Minecraft 版本与 Fabric / Forge / NeoForge / Quilt 元数据。
- 对已安装 `.jar` 使用可逆的 `.disabled` 方式开关，不删除原文件。
- 新建和编辑实例共用统一加载器模型，Minecraft 版本与 Loader 版本不再混为一谈。

</details>

## ✅ v1.2 兼容性地图

| 组合 | 当前定位 |
|---|---|
| **Minecraft 1.21.11 + Fabric** | 🟢 本次推荐的稳定组合 |
| Vanilla 与大量经典/远古版本 | 🟢 已完成重点兼容，实际表现仍受设备与版本资源影响 |
| Quilt | 🟡 已接入统一加载器与实例流程，建议按具体版本测试 |
| Minecraft 26.x | 🧪 可进入的新版本兼容路径仍在完善图形呈现 |
| Forge / NeoForge | 🧪 安装和启动链路已接入，部分版本仍需继续适配加载阶段 |

> [!TIP]
> 第一次体验建议从 **Minecraft 1.21.11 + Fabric** 开始。实验组合出现问题时，请附上 `latestlog.txt` 提交 Issue。

## 📱 系统要求

- iOS / iPadOS 14.0–27
- 64 位 arm64 iPhone 或 iPad
- 现代 Minecraft 通常需要 JIT、足够的可用内存和正确的签名权限
- 新版 Minecraft 与大型整合包推荐使用内存更充足的设备

## ⬇️ 安装

前往 [GitHub Releases](../../releases) 下载：

| 文件 | 用途 |
|---|---|
| `PocketJLauncher-v1.2-iOS.ipa` | 开发者签名、AltStore、SideStore 及兼容的 IPA 侧载方式 |
| `PocketJLauncher-v1.2-iOS-TrollStore.tipa` | 适用于受支持的 TrollStore 环境 |
| `SHA256SUMS.txt` | 校验下载文件是否完整、是否与发布产物一致 |

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

### Xcode

1. 打开 `PocketJLauncher.xcodeproj`。
2. 选择 **PocketJ Launcher** scheme。
3. 在 Signing & Capabilities 中选择自己的开发团队。
4. 连接 iPhone / iPad，Clean Build Folder 后运行。

### Makefile

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

感谢 Amethyst-iOS、PojavLauncher、Boardwalk、StikDebug、Fabric、Quilt、Modrinth 及所有第三方组件贡献者。上游代码版权归各自作者所有。

Copyright © 2026 Erico.

<p align="right"><a href="#pocketj-launcher">⬆️ 返回顶部</a></p>

---

# 🇬🇧 English

## Why PocketJ?

Many mobile Java launchers stop at opening the game. PocketJ aims to bring a complete desktop-launcher workflow to iOS: **JIT, instances, Java runtimes, mods, modpacks, accounts, controls, and diagnostics—all inside one native app.**

At the same time, PocketJ focuses not only on feature completeness, but also on improving the iOS Java runtime experience. Compared with earlier mobile Java launcher solutions, PocketJ introduces continuous optimizations across the launch pipeline, resource loading, rendering experience, and device adaptation, aiming to provide a faster, more stable Minecraft Java experience closer to desktop launchers on iPhone and iPad.

PocketJ is developed from the GPL-3.0 licensed [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) project and inherits substantial work from the [PojavLauncher](https://github.com/PojavLauncherTeam) and Boardwalk ecosystems. Version 1.2 keeps the mature JVM and launch core while adding PocketJ's own iOS-first workflows.

### 📸 See PocketJ running on real devices

Visit the [screenshot gallery](Example/README.md) to browse iOS 27, iPadOS 18, iPhone X + iOS 14, and Forge test galleries. Every compact preview opens its full-resolution image.

[![Screenshots](https://img.shields.io/badge/Screenshot%20Gallery-Real%20Device%20Tests-20c66b?style=for-the-badge&logo=apple&logoColor=white)](Example/README.md)

## ✨ What PocketJ brings to iOS

| PocketJ capability | What it gives you |
|---|---|
| ⚡ **Built-in JIT workflow** | Import this device's pairing file, inspect state, and enable JIT for PocketJ itself without leaving the launcher workflow |
| 🧩 **Native mod center** | Browse and search Modrinth, with project icons and compatibility filtering based on the selected instance |
| 🎛️ **Per-instance mod management** | Inspect installed mods, enable or disable them, check updates, and choose exact versions |
| 📦 **Unified instance and modpack entry** | Create an instance, import a ZIP, or browse online modpacks from one `+` menu; modpacks are isolated instead of replacing the active instance |
| ☕ **Smart Java selection** | Manage Java 8, 17, 21, and 25; automatically match game generations while retaining per-instance overrides |
| 🕰️ **Classic-version compatibility** | A dedicated legacy path adjusts Java-era memory and startup behavior without changing the modern path |
| ⏯️ **Resumable downloads** | Pause, resume, retry, and reuse valid local files instead of downloading everything again |
| 🎮 **Touch-first controls** | Original control editor, separated touch/controller mapping, and responsive eight-direction movement |
| 👤 **Microsoft and offline coexistence** | Separate account identities prevent same-name accounts from replacing each other; Minecraft avatar caching is included |
| 🧾 **Visible launch state** | JIT, downloads, loader installation, and game launch expose progress and exportable logs instead of silent black screens |

<details>
<summary><strong>⚡ How does built-in JIT work?</strong></summary>

- On iOS / iPadOS 17.4 and later, import this device's `.plist` or `.mobiledevicepairing` file inside PocketJ.
- Start LocalDevVPN, then enable JIT from PocketJ's Runtime page.
- PocketJ reports Waiting for Setup, Ready, Enabled, or Unavailable states.
- Starting from the home screen can enable JIT first and then continue into Minecraft.
- JIT, extended virtual address space, and increased memory limits are separate capabilities and still depend on the OS, signature, and entitlements.

</details>

<details>
<summary><strong>🧩 What is included in the mod workflow?</strong></summary>

- Built-in Modrinth search, icons, version selection, and compatibility filters.
- Optional CurseForge source support; source builders must configure a key under its API terms.
- Instance metadata detection for Minecraft and Fabric / Forge / NeoForge / Quilt.
- Reversible `.disabled` toggles for installed JAR files.
- One loader model shared by creation and editing, keeping Minecraft versions separate from loader versions.

</details>

## ✅ v1.2 compatibility map

| Combination | Current status |
|---|---|
| **Minecraft 1.21.11 + Fabric** | 🟢 Recommended stable combination for this release |
| Vanilla and many classic/legacy releases | 🟢 Compatibility work completed for the primary paths; results still vary with device and upstream assets |
| Quilt | 🟡 Connected to the unified loader workflow; test the exact version you need |
| Minecraft 26.x | 🧪 New-version path can launch, while graphics presentation still needs further work |
| Forge / NeoForge | 🧪 Installer and launch flows are integrated; some versions still require loader-stage compatibility work |

> [!TIP]
> For a first run, start with **Minecraft 1.21.11 + Fabric**. Attach `latestlog.txt` when reporting an experimental combination.

## 📱 Requirements

- iOS / iPadOS 14.0–27
- A 64-bit arm64 iPhone or iPad
- Modern Minecraft generally needs JIT, enough available memory, and appropriate signing entitlements
- Newer Minecraft releases and large modpacks benefit from newer devices

## ⬇️ Downloads

Get release assets from [GitHub Releases](../../releases):

| File | Purpose |
|---|---|
| `PocketJLauncher-v1.2-iOS.ipa` | Development signing, AltStore, SideStore, and compatible IPA sideloading methods |
| `PocketJLauncher-v1.2-iOS-TrollStore.tipa` | Supported TrollStore environments |
| `SHA256SUMS.txt` | Verifies release-file integrity |

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

### Xcode

1. Open `PocketJLauncher.xcodeproj`.
2. Select the **PocketJ Launcher** scheme.
3. Choose your development team under Signing & Capabilities.
4. Connect an iPhone or iPad, Clean Build Folder, and run.

### Makefile

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

Thanks to Amethyst-iOS, PojavLauncher, Boardwalk, StikDebug, Fabric, Quilt, Modrinth, and every third-party contributor. Copyright in upstream code remains with its respective authors.

Copyright © 2026 Erico.

<p align="right"><a href="#pocketj-launcher">⬆️ Back to top</a></p>
