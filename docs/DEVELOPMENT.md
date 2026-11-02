# 二次开发

先阅读[兼容性](COMPATIBILITY.md)与[架构](ARCHITECTURE.md)。当前是一套 RK98 实验适配加可复用领域逻辑，不是通用插件框架。

## 本地环境

在 Mac 上安装含 macOS 26+ SDK 的 Xcode / Command Line Tools，以及 Python 3。没有 Swift 包依赖；不用安装官方 Windows 驱动即可构建。脚本从仓库根目录工作，Swift 以兼容模式编译并明确设置 macOS 13 部署目标。

```sh
./scripts/build.sh build/development/FeralKey.app
open build/development/FeralKey.app
```

给开发构建使用独立输出路径，可保留日常应用文件。主应用仍使用历史 bundle ID `local.zephyr.rk98lab`，不同路径并不代表配置、单实例行为或系统权限完全隔离。编译签名变化后，可能需要重新添加输入监控授权。

首次仅验证软件流程：

```sh
python3 scripts/check-repository.py
python3 tests/RepositoryChecksTests.py
./scripts/test.sh
./scripts/test-auto-refresh.sh
./scripts/quota-smoke.sh
```

这些检查不连接账号或发送 HID。`quota-smoke.sh --live` 另行使用本机真实登录读取额度，仍不发送 HID；其输出不要提交。

## 扩展路径

| 目标 | 从哪里开始 | 必须保留的约束 |
| --- | --- | --- |
| 新灯效 / 音乐效果 | `Sources/Lighting.swift` 的渲染器和合成器、相关 Views | 尊重已应用额度区、亮度、时间尺度及停止后的恢复；不要从视图直接写设备 |
| 新通知 / 工作状态来源 | `Sources/Features.swift`、`LabModel.swift` 及系统来源层 | 有效性和未知状态明确；用户开启；复用确认、冷却、五秒恢复和会话取消 |
| 新额度提供方 | 参考 `CodexClient.swift` 和 `Quota.swift` | 独立认证边界；不复用 Codex 的账号逻辑；先明确数据窗口和失效规则 |
| 新键盘 / 连接方式 | `Discovery.swift`、布局资源、专用编码器及 `KeyboardTransport` 实现 | 精确匹配、能力和来源记录、完整事务测试、实物验证；不向新设备发送 RK98 命令 |

当前 `LabModel` 与 RK98 编码器存在直接连接。新品牌需要在代码中增加明确的选择和能力分发，并按需重构，不能宣称填一个 JSON 就能完成适配。`docs/adapters/rk98-258a-00c1.json` 仅是证据清单。

新增设备按[探索教程](KEYBOARD-GUIDE.md)收集设备身份、接口描述符、协议来源和具体版本；物理键位与 LED 索引分开建模。先验证编码、非法输入拒绝、设备错配拒绝及重连取消，再由拥有者操作备用设备逐项测试，标注实测范围。没有证据时保留未知或不支持。

## 只读研究

```sh
./scripts/probe-receiver.sh          # 接收器元数据
./scripts/probe-bluetooth.sh         # 精确名称目标的标准 GATT 读取
```

它们不会完成无线灯控适配。蓝牙脚本使用独立诊断应用，需要用户决定是否允许蓝牙访问。受限 Feature 06 读取的额外条件见[接收器说明](research/RECEIVER-25A7-FA70.md)。默认把输出留在已忽略的 `evidence/`，不注册原始按键回调，不枚举未知写命令。

## 文档和发布流程变更

```sh
python3 tests/PackagingTests.py
```

打包检查会在隔离副本中编译应用，验证源码 ZIP 在没有 Git 的情况下可构建。新增根目录的发布文件需更新 `scripts/package.sh` 的允许清单及对应夹具；运行时资源同样使用允许清单。不要扩大成复制整个工作目录。

提交前检查差异和脱敏内容，参阅[贡献指南](../CONTRIBUTING.md)。GitHub Actions 不运行硬件探测、真实额度读取、签名凭据上传或自动发布。
