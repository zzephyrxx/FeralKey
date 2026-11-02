# RK98 蓝牙研究

核对日期：2026-10-31。**本机已成功连接蓝牙诊断客户端、识别设备并读取标准电量；蓝牙 RGB 控制尚未打通。** 额度灯、通知灯、音乐律动和硬件改键仍不能通过此次诊断工具使用。

## 本机结果

| 项目 | 实测值 |
| --- | --- |
| HID 名称 | `RK98RGB 5.0 `，末尾有空格 |
| HID 厂商 / 连接 | BEKEN / Bluetooth Low Energy |
| VID:PID | `000E:3412`，与 USB 模式不同 |
| VersionNumber | `6701`（十六进制）；不据此推断主控固件版本 |
| 软件版本特征值 | `02.0` |
| 标准电池特征值 | `100%`，本次读取时的快照 |
| GATT 发现 | `180A` Device Information、`180F` Battery |
| GATT 可写特征 | 本次可见服务中未发现 |

标准值来自真实设备读取，不是模拟数据。PnP ID `2A50` 返回 `02 0e 00 12 34 01 67`，与 HID 的厂商、产品及版本元数据一致。电量服务支持通知，但本次仅执行一次读取，没有订阅。

GATT 的四个可见特征为 `180A/2A29`（厂商）、`180A/2A28`（软件版本）、`180A/2A50`（PnP ID）、`180F/2A19`（电量）；均不支持 Write 或 Write Without Response。完整发现返回无错误。

HID 元数据报告最大输入 21 字节、最大输出 2 字节、最大 Feature 1 字节。**报告描述符内实际没有 Feature 主项**，不能把最大 Feature 的属性值理解为存在可用的厂商命令。描述符包含：

- Report 1：普通键盘输入、一个厂商输入字节，以及标准五个键盘指示灯的输出位和填充。
- Report 2：NKRO 键盘输入。
- Report 3：媒体按键输入。
- Report 4：系统按键输入。

唯一输出属于标准键盘指示灯，不能当作逐键 RGB；未找到有线模式使用的 65 字节 Feature `0A`。没有向该输出发送测试数据，也没有尝试把有线命令缩短后发送。

## 结论的范围

GATT 列表是 macOS CoreBluetooth 实际向应用提供的结果，不保证列出了设备的所有底层服务。尤其本次没有通过 CoreBluetooth 看到系统正在使用的 HID 服务 `1812`，因此另行检查了 IOHID 提供的报告描述符。两条路径均未提供已知的 RGB 控制通道。

这些结果说明**当前没有足够依据实现这把 RK98 的蓝牙灯控**，不能证明设备硬件永远无法支持。仅靠蓝牙已配对、可以打字、电量可读或具有 RGB 背光，都不足以推出电脑可以通过蓝牙控制 RGB。

下一步需要同型号蓝牙版本的厂商控制服务/命令资料，或能实际控制该版本蓝牙灯光的软件及其通信样本。未知厂商服务、隐藏命令、配对写入和固件升级均未尝试。当前没有要求用户安装 Windows 或拆机。

## 可复现诊断

保持 RK98 已通过蓝牙连接，在源码目录执行：

```sh
./scripts/probe-bluetooth.sh
```

脚本构建独立的 `build/FeralKeyBluetoothProbe.app`。若 macOS 请求「FeralKey 蓝牙诊断」的蓝牙访问权限，需由用户手动决定是否允许。它不替换主应用，也不沿用或修改主应用的输入监控授权。

脚本先枚举 `000E:3412`、精确匹配标准化名称及 BLE 连接的 HID 元数据，再使用 CoreBluetooth 查找已连接/正在广播、名称匹配的唯一目标。名称不是加密身份验证，因此此工具只允许读取标准元数据，不能作为将来写操作的身份门槛。若出现多个匹配目标则停止。扫描最多 8 秒，选定设备后的发现最多 20 秒，总等待最多 90 秒。

读取白名单按「服务 + 特征」绑定：

- `1800`：`2A00`、`2A01`；`180A`：`2A24`、`2A26`、`2A27`、`2A28`、`2A29`、`2A50`。
- `180F`：`2A19`；`1812`：`2A4A`、`2A4B`；如可见，只读取 HID Report 的 `2908` 报告引用描述符，不读取 Report 内容。

不读取序列号 `2A25`、按键输入 Report、Boot Keyboard Input、HID 控制/协议特征或任意厂商特征值；不订阅通知、不写 CCCD、不写灯光/改键/固件、不删除配对。结束时只释放本诊断客户端的连接。输出不包含设备地址、CoreBluetooth 外设标识符或配对密钥。

结果位于已被 Git 忽略的 `evidence/bluetooth-rk98/hid-metadata.json` 和 `gatt-services.json`。`discovery_completed` 只表示发现和允许的读取结束，不表示支持 RGB；电量值是当时快照。其他状态（包括权限拒绝、目标不可见或发现超时）应按原文排查，不能据此断言硬件不支持。

只构建、不访问设备：

```sh
./scripts/probe-bluetooth.sh --build-only
```

离线读取策略测试已加入 `scripts/test.sh`，覆盖目标名称边界、服务/特征绑定、输入和序列号拒绝、异常电量长度/范围、文本及载荷大小限制。测试不连接蓝牙设备。

## 资料

- [Apple CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) 与本机 SDK 的 `CBCentralManager.h`、`CBPeripheral.h`、`CBManager.h` 用于核对公开 API；没有调用私有蓝牙接口。
- [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html) 用于核对标准服务及特征编号；不把标准电池服务解释为厂商 RGB 控制服务。

本次不更换日常使用的 `build/FeralKey.app`。新增的是可复现诊断工具，不是蓝牙灯控发行版。
