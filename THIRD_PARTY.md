# 第三方来源与许可

本项目以 GPL-3.0-or-later 发布，完整许可见 LICENSE。

## Rangoli

- 项目：https://github.com/rnayabed/rangoli
- 作者：Debayan Sutradhar (rnayabed)，Copyright (C) 2023
- 检查的提交：`503cdc3b5c630d56b14d7f18533f57e39583a7db`
- 许可：GPL-3.0-or-later
- `Resources/rk98-layout.json` 来自 `keyboards/258a/configs/c1.json`。
- `Resources/keycodes.json` 是 `src/keycode.h` 中按键枚举的 JSON 转换。
- `Sources/Protocol.swift` 的报告格式改写自 `src/keyboardconfiguratorcontroller.cpp`，模式值依据 `src/modemodel.h`，HID 接口选择依据 `src/hidconnectionworker.cpp`。
- 原作者的工作已覆盖本设备编号，无需声称重新独立破解了协议。
- 0.3 的逐键 RGB 编码同样改写自上述保存流程：模式 14、7 包颜色报告、按 `bufferIndex × 3` 放置 RGB。未复制其自动同时保存按键映射的行为。

## Kludge Knight

- 项目：https://github.com/vinc3m1/kludgeknight
- 检查的提交：`b7b0359c3f7ce0e9f3d102075ff98d286ce1e6a8`
- 用于交叉核对 `src/models/LightingCodec.ts`、`ProtocolTranslator.ts` 与 `docs/lighting-protocol.md`。
- 未复制该项目代码。该项目文档中的 RGB 模式编号示例与 Rangoli 枚举存在冲突，本工具使用 Rangoli 实际枚举：17 常亮、18 呼吸。

## 官方与系统资料

- Codex 官方 App Server 文档：https://learn.chatgpt.com/docs/app-server ，`initialize` / `account/rateLimits/read`。通过独立安装的 Codex 可执行文件交互；未复制或打包 Codex 源码/二进制。

- RK 下载中心：https://www.rkgaming.com/download/
- Apple IOHIDDeviceOpen：https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen
- macOS 当前 SDK 的 IOHIDLib.h、IOHIDProperties.h 与系统 hidutil 帮助用于核对 API。

## Solid Glass（外观设计参考）

- 项目：https://github.com/deeplethe/solid-glass
- 作者：DeepLethe，Copyright (c) 2026
- 检查的提交：`6e8903e494a15491ceda38fafea5056c95a74d44`
- 许可：MIT，全文随 `Resources/SolidGlass-LICENSE.txt` 提供，构建时附在应用资源中。
- 参考 `src/solid-glass.css` 的中性明暗色阶、pane/card/control 材质分层、顶缘反光、细边和接触阴影。没有引入 React/CSS 运行时，用 SwiftUI 与 macOS 原生玻璃 API 重新实现。
- 本应用继续采用 GPL-3.0-or-later；上述参考项目的 MIT 版权声明独立保留。

## 0.5 通知横幅实现参考

- Apple UserNotifications 的 `getDeliveredNotifications` 仅返回本应用通知：[官方说明](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications(completionhandler:))。
- [BannerHither](https://github.com/KJeon10/BannerHither) 用于确认通过 Accessibility 观察通知中心界面元素的思路。
- [PingPlace issue 44](https://github.com/NotWadeGrimridge/PingPlace/issues/44) 用于核对 macOS 26 堆叠横幅的 `AXNotificationCenterAlertStack` 子角色及通知子元素 UUID 标识符。
- 未复制上述通知项目的实现代码。FeralKey 自行实现有界、只读元数据扫描；这些界面标识不属于稳定的跨版本通知订阅协议，仍需在目标系统实测。

## SignalRGB RK 家族实时协议资料（0.8）

- [RK84 插件固定提交](https://gitlab.com/signalrgb/signal-plugins/-/blob/92dfc19414f3031f65d7e78b50b903908fedda53/Plugins/Royal%20Kludge/RK_84_Keyboard.js)，作者标注 Mizzen。blob `03e6881fe88a2fdfd68ba666f06a30368e6aaecd`，内容 SHA-256 `1067a657d9ae198256fbd8b43a33be95f80e12ebd6598770a8f61f70e9078907`，核对日期 2026-10-30。
- RK61 同目录插件用于交叉核对帧头、分包和停流回固件的描述。
- 本项目参考协议字段和矩阵地址规律，自行编写 Swift 编码器、并发控制与合成器，没有复制或分发插件实现文件。
- 上游列出的设备不含本机 RK98 PID `00C1`；仅提供一次确认后的实验家族通道，不能宣称上游已支持或本机已实测成功。

## UI design reference (0.9)

The grouped settings layout and row spacing in the public [FanBar screenshots](https://github.com/helson-lin/FanBar#-screenshots) informed FeralKey's independently implemented disclosure rows. No FanBar source, icons, logo or screenshot assets are incorporated into the app or release archives.

## 2.4G 接收器研究参考

2026-10-31 核对 PULSE 的 RK R98 研究、RK 软件研究项目的 20 字节无线通道、Redragon 控制器的接口筛选，以及 Keylux 对短状态通道与颜色通道的区分。固定提交、文件及不匹配点见 [研究记录](docs/research/RECEIVER-25A7-FA70.md)。仅参考协议与接口证据，没有复制这些项目的运行实现，也没有将其他型号的命令发送到本机接收器。

## 蓝牙只读诊断

2026-10-31 使用 Apple CoreBluetooth 公开 API 与 Bluetooth SIG Assigned Numbers 核对标准服务/特征编号。来源及本机实测边界见 [蓝牙研究记录](docs/research/BLUETOOTH-RK98.md)。实现为本项目自行编写，未复制其他键盘的蓝牙命令或厂商驱动。
