<div align="center">
  <img src="icon1.png" width="96" alt="PocketJ Launcher Icon">
  <img src="icon2.png" width="280" alt="PocketJ Launcher Banner">
  <h1>PocketJ Launcher</h1>
  <p><strong>专为iPhone和iPad设计：掌上 Java，随时开玩。</strong><br>Apple-native Minecraft: Java Edition launcher for iPhone and iPad.</p>

  <p>
    <a href="#-简体中文">简体中文</a>
    ·
    <a href="#-english">English</a>
  </p>

  <p>
    <img alt="Version" src="https://img.shields.io/badge/version-v1.0-20c66b?style=for-the-badge">
    <img alt="Platform" src="https://img.shields.io/badge/iOS%20%7C%20iPadOS-14%2B-111111?style=for-the-badge&logo=apple&logoColor=white">
    <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-7c5cff?style=for-the-badge">
    <img alt="Languages" src="https://img.shields.io/badge/UI-中文%20%7C%20English-28a8ea?style=for-the-badge">
  </p>
</div>

---

# 🇨🇳 简体中文

## ✨ 这是什么？

**PocketJ Launcher（掌上Java启动器）** 是由 **Erico** 维护的 iOS / iPadOS 开源 Minecraft: Java Edition 启动器。

它基于 GPL-3.0 项目 [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) 持续开发，并继承了 PojavLauncher 与 Boardwalk 生态中的大量工作。PocketJ 在此基础上带来了重新设计的 Apple 原生界面、简体中文与英文双语支持、实例与账户工作流优化、诊断工具、控制体验改进及新版 iOS 兼容修复。

> [!IMPORTANT]
> PocketJ Launcher 不是 Mojang Studios 或 Microsoft 的官方产品。Minecraft 是 Microsoft Corporation 的商标。

## 🚀 功能亮点

| 能力 | 说明 |
|---|---|
| 🍎 Apple 原生界面 | 面向 iPhone 与 iPad 重新设计，支持深色模式、动态字体与系统原生交互 |
| ☕ 多 Java Runtime | 随版本需求管理 Java 8、17、21 与 25 运行环境 |
| 🧩 模组生态 | 支持常见的 Fabric、Forge、Quilt 与 OptiFine 游戏配置 |
| 📦 实例管理 | 创建、导入、整理与隔离不同 Minecraft 实例和整合包 |
| 🎮 多种输入 | 支持触屏控制布局、键盘、鼠标与游戏手柄 |
| 👤 账户支持 | 支持 Microsoft 正版账户、演示模式和离线账户 |
| 🛠️ 可见诊断 | 启动失败不会静默处理，可查看和导出原始日志 |
| 🌐 中英双语 | 应用界面支持简体中文与英文，并跟随应用语言设置 |

离线账户可以下载并游玩 Minecraft，但不能进入 Minecraft Realms 或其他需要正版在线验证的服务器。我们仍然建议通过官方渠道购买 Minecraft。

## 📱 系统要求

- iOS / iPadOS 14.0 或更高版本
- 已为最新的 iOS / iPadOS 27 准备好 🎉
- 64 位 arm64 设备
- 推荐使用较新的 iPhone 或 iPad，以获得更稳定的图形和内存表现
- 运行现代 Minecraft 通常需要可用的 JIT

> [!NOTE]
> JIT 是否可用取决于系统版本、安装方式、签名权限和所使用的 JIT 工具。JIT、扩展虚拟地址空间与更高内存限制是不同能力，不能互相替代。

## ⚡ 安装与 JIT

PocketJ 必须使用能够提供所需 entitlement 的方式进行签名和安装。常见方案包括开发者证书、AltStore、SideStore、TrollStore，以及兼容当前系统版本的调试/JIT 工具。

| 方式 | 是否可能提供 JIT | 备注 |
|---|:---:|---|
| Xcode / 开发者证书 | ✅ | 适合开发、调试和真机测试 |
| AltStore / SideStore | ✅ | 具体步骤取决于系统版本与配套工具 |
| StikDebug | ✅ | 新系统可能需要 Universal JIT 脚本 |
| TrollStore / 越狱环境 | ✅ | 仅适用于受支持的设备与系统 |
| 普通分发证书安装 | ⚠️ | 通常无法提供 Java 所需的完整 JIT 能力 |

只从可信来源安装 PocketJ Launcher 和相关签名/JIT 工具。

## 🧑‍💻 从源码构建

### 准备

- macOS 与 Xcode
- Xcode Command Line Tools
- Homebrew 环境中的 `gmake`、`cmake`、`wget`、`ldid` 等构建工具
- Java 8 Boot JDK；Xcode 构建脚本在本机不存在 Java 8 时会准备缓存版本

### Xcode

1. 打开 `PocketJLauncher.xcodeproj`。
2. 选择 **PocketJ Launcher** scheme。
3. 在 Signing & Capabilities 中选择你自己的开发团队。
4. 连接设备并运行。

### Makefile

```bash
gmake payload PLATFORM=2 BOOTJDK="/path/to/jdk8/bin"
```

构建产物会生成在 `artifacts/`。不同安装环境需要不同 entitlement，请在分发前确认签名内容。

<details>
<summary><strong>🧭 项目结构</strong></summary>

```text
PocketJLauncher.xcodeproj   Xcode 真机构建入口
XcodeRunner/                Xcode 包装 target 与构建脚本
Natives/                    iOS UI、启动器桥接和原生运行层
JavaApp/                    Java 启动器与 LWJGL 兼容代码
Makefile                    原生、Java、Runtime 与打包流程
NOTICE.md                   修改声明及上游项目归属
LICENSE                     GNU GPL v3 完整文本
```

</details>

## 🤝 贡献与反馈

- 提交问题前，请附上设备型号、系统版本、PocketJ 版本、复现步骤及 `latestlog.txt`。
- UI、翻译、兼容性、实例管理与文档改进都欢迎提交 Pull Request。
- 安全问题请不要在公开 Issue 中附带账户令牌、签名证书或私人日志。

## 💬 建议、问题与交流

如果你有功能建议、改进意见或发现了问题，欢迎通过 [GitHub Issues](../../issues/new/choose) 提交。我们会持续改进和优化这个项目。

[![Telegram](https://img.shields.io/badge/Telegram-加入交流群-26A5E4?logo=telegram&logoColor=white)](https://t.me/+wqBdm5YDqR8yYTNl)
[![QQ群](https://img.shields.io/badge/QQ群-1062592009-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/)

QQ群号：`1062592009`

## 👨‍🚀 维护者

**Erico** · [@EricoEC](https://github.com/EricoEC)

项目主页：[github.com/EricoEC/PocketJLauncher](https://github.com/EricoEC/PocketJLauncher)

## 📜 许可证与致谢

PocketJ Launcher 采用 **GNU General Public License v3.0** 发布。修改和分发时必须继续遵守 GPL-3.0，并保留适用的版权、许可证、无担保声明以及对应源代码义务。详见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。

感谢 Amethyst-iOS、PojavLauncher、Boardwalk 以及所有第三方组件贡献者。各上游代码的版权仍归其各自作者所有。

Copyright © 2026 Erico. All Rights Reserved.

<p align="right"><a href="#pocketj-launcher">⬆️ 返回顶部</a></p>

---

# 🇬🇧 English

## ✨ What is PocketJ?

**PocketJ Launcher** is an open-source Minecraft: Java Edition launcher for iOS and iPadOS, maintained by **Erico**.

It is developed from the GPL-3.0 licensed [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) project and inherits substantial work from the PojavLauncher and Boardwalk ecosystems. PocketJ adds a redesigned Apple-native interface, Simplified Chinese and English localization, improved instance and account workflows, visible diagnostics, control refinements, and compatibility fixes for newer iOS releases.

> [!IMPORTANT]
> PocketJ Launcher is not an official Mojang Studios or Microsoft product. Minecraft is a trademark of Microsoft Corporation.

## 🚀 Highlights

| Capability | Description |
|---|---|
| 🍎 Apple-native UI | Redesigned for iPhone and iPad with Dark Mode, Dynamic Type, and system-native interaction |
| ☕ Multiple runtimes | Manages Java 8, 17, 21, and 25 environments for different game versions |
| 🧩 Mod ecosystem | Supports common Fabric, Forge, Quilt, and OptiFine configurations |
| 📦 Instance management | Create, import, organize, and isolate Minecraft instances and modpacks |
| 🎮 Flexible input | Touch layouts, keyboard, mouse, and game controller support |
| 👤 Account options | Microsoft accounts, demo mode, and offline accounts |
| 🛠️ Visible diagnostics | Launch failures are exposed through readable and exportable logs |
| 🌐 Bilingual UI | Simplified Chinese and English, following the app-specific language setting |

Offline accounts can download and play Minecraft, but cannot join Minecraft Realms or servers that require online authentication. Purchasing Minecraft through an official channel is still recommended.

## 📱 Requirements

- iOS or iPadOS 14.0 and later
- Ready for the latest iOS / iPadOS 27 🎉
- A 64-bit arm64 device
- A newer iPhone or iPad is recommended for better graphics and memory performance
- Modern Minecraft versions generally require working JIT support

> [!NOTE]
> JIT availability depends on the OS version, installation method, signing entitlements, and JIT utility. JIT, extended virtual address space, and increased memory limits are separate capabilities.

## ⚡ Installation and JIT

PocketJ must be installed with a signing method capable of providing the required entitlements. Common options include a development certificate, AltStore, SideStore, TrollStore, and debugging/JIT tools compatible with the installed iOS version.

| Method | JIT may be available | Notes |
|---|:---:|---|
| Xcode / development signing | ✅ | Best suited to development and on-device testing |
| AltStore / SideStore | ✅ | Setup varies by OS version and companion tools |
| StikDebug | ✅ | New systems may require the Universal JIT script |
| TrollStore / jailbreak | ✅ | Only on supported devices and OS versions |
| Regular distribution signing | ⚠️ | Usually cannot provide all capabilities required by Java |

Install PocketJ Launcher and signing/JIT tools only from sources you trust.

## 🧑‍💻 Building from source

### Prerequisites

- macOS and Xcode
- Xcode Command Line Tools
- Build tools such as `gmake`, `cmake`, `wget`, and `ldid` from Homebrew
- A Java 8 Boot JDK; the Xcode build wrapper prepares a cached copy when Java 8 is unavailable locally

### Xcode

1. Open `PocketJLauncher.xcodeproj`.
2. Select the **PocketJ Launcher** scheme.
3. Select your own development team under Signing & Capabilities.
4. Connect a device and run.

### Makefile

```bash
gmake payload PLATFORM=2 BOOTJDK="/path/to/jdk8/bin"
```

Build output is written to `artifacts/`. Different installation environments require different entitlements; inspect the final signature before distribution.

<details>
<summary><strong>🧭 Repository layout</strong></summary>

```text
PocketJLauncher.xcodeproj   Xcode entry point for device builds
XcodeRunner/                Wrapper target and Xcode build script
Natives/                    iOS UI, launcher bridge, and native runtime layer
JavaApp/                    Java launcher and LWJGL compatibility code
Makefile                    Native, Java, runtime, and packaging pipeline
NOTICE.md                   Modification notice and upstream attribution
LICENSE                     Full GNU GPL v3 license text
```

</details>

## 🤝 Contributing and support

- Bug reports should include the device, iOS version, PocketJ version, reproduction steps, and `latestlog.txt`.
- Pull requests for UI, localization, compatibility, instance management, and documentation are welcome.
- Never post account tokens, signing certificates, or private logs in public issues.

## 💬 Ideas, issues, and community

Have a feature request, an improvement idea, or a bug to report? Open a [GitHub Issue](../../issues/new/choose). We will continue improving and refining the project.

[![Telegram](https://img.shields.io/badge/Telegram-Join%20the%20community-26A5E4?logo=telegram&logoColor=white)](https://t.me/+wqBdm5YDqR8yYTNl)
[![QQ Group](https://img.shields.io/badge/QQ%20Group-1062592009-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/)

QQ group: `1062592009`

## 👨‍🚀 Maintainer

**Erico** · [@EricoEC](https://github.com/EricoEC)

Project home: [github.com/EricoEC/PocketJLauncher](https://github.com/EricoEC/PocketJLauncher)

## 📜 License and acknowledgements

PocketJ Launcher is distributed under the **GNU General Public License v3.0**. Modified versions and binary distributions must continue to comply with GPL-3.0, including applicable source, copyright, license, and warranty-notice obligations. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Thanks to the contributors of Amethyst-iOS, PojavLauncher, Boardwalk, and every bundled third-party component. Copyright in upstream code remains with its respective authors.

Copyright © 2026 Erico. All Rights Reserved.

<p align="right"><a href="#pocketj-launcher">⬆️ Back to top</a></p>
