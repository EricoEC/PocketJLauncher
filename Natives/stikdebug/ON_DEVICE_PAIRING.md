# v1.6 本机配对

JIT → 连接准备 →「免电脑：本机配对」。仅 iOS 27+ 可开始；电脑生成、
文件导入、iLoader Documents 同步、导出、删除及独立 JIT Helper 继续保留。

启动后允许本地网络及通知，开启 Wi-Fi 和开发者模式，进入系统设置的
「隐私与安全性 → 开发者模式」，选择与 PocketJ Launcher 配对并输入 PIN。
通知被拒绝时可回到配对页查看或复制 PIN。返回上一级、取消或三分钟超时会
终止监听和保活。只在本次配对期间播放静音音频维持切换设置时的后台监听。

配对结果先交给旧 `rp_pairing_file_from_bytes` 校验，再保存至原有
Application Support/Pairing/pairingFile.plist 与 Documents/pairingFile.plist。
新记录同时保存主机 altIRK，旧解析器忽略额外字段。原文件仅在成功后替换。
完成配对不会自动开启 JIT，仍使用 LocalDevVPN 与原有开启按钮。

第三方源码入口、Rust 包装、锁文件、源码校验和及许可证集中在
`iOS版本/SharedDependencies/PocketJ/Vendor/PocketJPairing`；详细复用路径见
该目录 README。编译缓存置于 `~/Library/Caches/PocketJPairing/target`。
Xcode 原有构建入口会编译、嵌入并签名独立 dylib，不替换 StikJIT 静态库。

参考：
- https://github.com/jkcoxson/idevice
- https://github.com/StikDebug/StikPair
- https://github.com/LinkPass888/AirBeep

验收边界：构建与包内组件检查由开发侧完成。iOS 27 真机首次配对、错误 PIN、
拒绝权限、后台往返、取消重试、电脑导入回归及 JIT 激活由用户真机验证。

## v1.6 界面整理

JIT 首页仅显示运行状态、配对文件、LocalDevVPN 与开启按钮。配对文件二级页
保留本机配对、已有文件导入、导出和删除；「从电脑导入」直接打开指定的
GitHub 配对工具发布页。LocalDevVPN 优先通过 `localdevvpn://` 打开，无法打开
时回退 App Store。页面前台可见时每秒探测一次实际调试端点，单次上限 600ms；
离开页面/后台停止轮询，返回立即重查，过期回调不覆盖当前结果。

凭据校验并保存成功后进入独立成功状态，显示成功页及返回 JIT 设置按钮。
后台完成发送完成通知，前台/返回前台提供一次成功触感；原有配对码通知保留。
