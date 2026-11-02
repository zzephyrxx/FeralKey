# FeralKey 文档

首次使用请先看兼容范围。当前只有 RK98-100KRGB N / USB `258A:00C1` 的实验控制适配，不能把设备被识别理解为灯光协议已支持。

## 使用

| 文档 | 内容 |
| --- | --- |
| [兼容性](COMPATIBILITY.md) | 精确设备身份、连接方式、系统范围与验证等级 |
| [使用指南](USER-GUIDE.md) | 构建后的首次连接、额度灯、灯效、通知、音乐与工作流 |
| [权限排查](PERMISSIONS.md) | 输入监控与临时签名变化导致的连接问题 |
| [实物验收](TESTING.md) | 安全的逐步检查；区别软件测试与硬件效果 |
| [额度读取](CODEX-QUOTA.md) | 本机 Codex 子进程、数据有效性与隐私 |

## 开发与发布

| 文档 | 内容 |
| --- | --- |
| [技术架构](ARCHITECTURE.md) | 分层、状态、数据流、并发与传输边界 |
| [开发指南](DEVELOPMENT.md) | 构建、测试、效果扩展、数据源和设备适配 |
| [键盘探索教程](KEYBOARD-GUIDE.md) | 从接口扫描到协议证据及适配验证 |
| [RK98 证据清单](adapters/rk98-258a-00c1.json) | 设备匹配、协议来源与验证状态；不是可执行插件 |
| [发布准备](PUBLISHING.md) | GitHub 项目简介、Topics、源码上传与分发边界 |
| [贡献指南](../CONTRIBUTING.md) | Issue、PR 与适配贡献要求 |
| [安全说明](../SECURITY.md) | 问题报告、数据脱敏及实验风险 |
| [第三方来源](../THIRD_PARTY.md) | 许可、固定提交和协议资料归属 |

## 研究与历史

- [2.4G 接收器](research/RECEIVER-25A7-FA70.md)：识别及受限状态读取，无 RGB 控制。
- [蓝牙 RK98](research/BLUETOOTH-RK98.md)：标准设备信息及电量可读，无 RGB 控制。
- [初期调研](research/RESEARCH-2026-10-29.md)：早期候选和探索方向，不代表当前兼容承诺。
- [更新记录](../CHANGELOG.md)：按版本索引功能与验证记录。
- [历史审查](reviews/ROUND-1.md)、[复审](reviews/ROUND-2.md)、[修复记录](reviews/FIXES.md)：仅对应当时的代码范围，不代表后续提交都经过同等审查。

历史文档可能描述已移除的功能。当前行为以首页、兼容性说明和实际源码为准。
