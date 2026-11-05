# PocketJ Launcher v1.6

## 简体中文

v1.6 集中完善本机配对、JIT 连接与原生界面，并补齐中文搜索、实例固定版本和首页 JAR 入口。本说明只列本版变化；既有 Minecraft 兼容、Java 运行时、模组管理与资源工作流继续保留，不重复计为新增。

### 本次新增与修复

- **免电脑配对：** iOS / iPadOS 27 及以上可直接在本机生成配对文件；通过通知查看配对码，在系统设置确认。文件校验并保存后显示成功页，补充后台完成通知与一次成功触感。保留取消、超时和重新配对。
- **JIT 与连接：** 首页精简为运行状态、配对文件、LocalDevVPN 和开启操作；导入、导出、删除移至二级页。前台可见时每秒检测连接，返回应用立即刷新；点击 LocalDevVPN 优先打开 App，未安装时转 App Store。电脑配对工具和已有文件导入继续保留。
- **中文模组搜索：** 扩充内置离线名称与别名索引，支持简繁体匹配；无需手动导入 CSV，未知搜索词保留原文。随包保留数据来源与许可说明。
- **实例版本：** 将 `latest-release` / `latest-snapshot` 解析为具体版本；已有实例的 Minecraft 基础版本固定显示并禁止意外修改，无法识别时给出明确提示。
- **界面与控制：** 修正控制页说明文字与触控 / 手柄切换条重叠，长规则按需展开；改善 Java 管理、实例设置和输入控件在不同宽度下的排布与换行。
- **运行 JAR：** 启动页增加「运行 .jar 文件」入口，复用现有 Java 执行流程，并补齐文件选择回调。

### 📥 下载

- GitHub Releases: https://github.com/EricoEC/PocketJLauncher/releases
- 123 云盘: https://1842976282.share.123pan.cn/123pan/5B6UTd-KLi1A
- 电脑配对工具：[配对工具 v1.0](https://github.com/EricoEC/PocketJLauncher/releases#release-pairing-tool-v1.0)

### 文件

| 文件 | 用途 |
|---|---|
| `PocketJLauncher-v1.6-iOS.ipa` | AltStore、SideStore 等兼容的 IPA 侧载方式；安装工具按需重新签名 |
| `PocketJLauncher-v1.6-iOS-TrollStore.tipa` | 受支持的 TrollStore 环境，使用对应的 TrollStore entitlement |
| `SHA256SUMS.txt` | 校验两个安装包 |

普通 IPA 不包含个人开发者 provisioning profile 或设备 UDID；安装工具需要使用用户自己的签名配置。TIPA 不代表所有系统均支持 TrollStore。

### 使用说明

- 本机配对入口：设置 → 运行环境 → JIT → 配对文件 → 本机配对。
- 电脑配对入口：「从电脑导入」打开发布页；获得文件后选择「导入已有文件」，也可由电脑工具直接传入 PocketJ。
- 配对成功后仍需连接 LocalDevVPN，再开启 JIT。iOS 26 及以上使用随包的独立 JIT Helper；17.4–25 的现有入口交给独立 StikDebug；14–17.3 需使用其他受支持的 JIT 方式。

### 构建与验证

- 应用及 JIT Helper 版本统一为 `1.6`，主包标识保持 `com.Erico.PocketJLauncher`。
- 归档前的开发版已覆盖安装到 iPhone 16 Pro Max；本机配对由用户反馈成功。
- 最终 Xcode Release 构建通过；两个安装包的 ZIP 完整性、分包权限与 SHA-256 校验通过。
- 已移除个人 provisioning profile、设备 UDID 和个人开发者签名；配对模块、JIT Helper 与第三方许可声明均随包保留。
- 游戏、加载器、模组及侧载签名组合较多，构建和包检查不代表每种组合都已完成真机验证。

## English

Version 1.6 focuses on on-device pairing, JIT connections, and native layouts, with improvements to Chinese search, pinned instance versions, and the home-page JAR entry. Existing Minecraft compatibility, Java runtimes, mod management, and resource workflows are retained rather than presented as new features.

### Changes

- **Computer-free pairing:** Generate a pairing file on iOS / iPadOS 27 and later. Read the PIN from a notification and approve it in system Settings. Successful validation and saving show a completion page, with a background completion notification and one success haptic. Cancellation, timeout, and re-pairing remain available.
- **JIT and connections:** Simplify the main page to runtime state, pairing file, LocalDevVPN, and the enable action. Move import/export/deletion into a secondary page. Check connectivity every second while visible in the foreground and immediately on returning. Open LocalDevVPN first, falling back to the App Store. Keep computer pairing and existing-file import.
- **Chinese mod search:** Expand the bundled offline name/alias index and match Simplified/Traditional Chinese. Manual CSV import is no longer needed; unknown queries remain unchanged. Include data attribution and licensing notices.
- **Instance versions:** Resolve `latest-release` / `latest-snapshot` to concrete versions. Pin an existing instance's base Minecraft version, prevent accidental edits, and report unidentified versions clearly.
- **Layouts and controls:** Fix overlapping control-page descriptions and the touch/controller selector. Expand longer rules on demand and improve wrapping and accessory sizing in Java management and instance settings.
- **Run JAR:** Add a Run .jar File entry on the launch page, reuse the existing Java execution flow, and complete its document-picker callback.

### 📥 Downloads

- GitHub Releases: https://github.com/EricoEC/PocketJLauncher/releases
- 123 Cloud: https://1842976282.share.123pan.cn/123pan/5B6UTd-KLi1A
- Computer pairing tool: [Pairing Tool v1.0](https://github.com/EricoEC/PocketJLauncher/releases#release-pairing-tool-v1.0)

### Files

| File | Purpose |
|---|---|
| `PocketJLauncher-v1.6-iOS.ipa` | Compatible IPA sideloading methods such as AltStore and SideStore; the installer re-signs as needed |
| `PocketJLauncher-v1.6-iOS-TrollStore.tipa` | Supported TrollStore environments, with the corresponding entitlements |
| `SHA256SUMS.txt` | Verifies both packages |

The ordinary IPA contains no personal developer provisioning profile or device UDIDs. Installers must apply the user's signing configuration. A TIPA does not imply TrollStore support on every OS version.

### Usage

- On-device pairing: Settings → Runtime → JIT → Pairing File → On-device Pairing.
- Computer pairing: Import from Computer opens the release page. Then choose Import an Existing File, or let the tool send the file directly to PocketJ.
- After pairing, connect LocalDevVPN and enable JIT. iOS 26 and later use the bundled independent JIT Helper; the existing iOS 17.4–25 entry hands off to independent StikDebug. iOS 14–17.3 needs another supported JIT method.

### Build and verification

- App and JIT Helper versions are aligned to `1.6`; the main bundle ID remains `com.Erico.PocketJLauncher`.
- The pre-archive development build was overlay-installed on iPhone 16 Pro Max; the user confirmed successful on-device pairing.
- Final Xcode Release build, ZIP integrity, variant-entitlement checks, and SHA-256 verification passed for both packages.
- Personal provisioning profiles, device UDIDs, and personal developer signatures were removed. The pairing module, JIT Helper, and third-party notices are included.
- Build and package checks do not establish device acceptance for every game, loader, mod, or sideload-signing combination.
