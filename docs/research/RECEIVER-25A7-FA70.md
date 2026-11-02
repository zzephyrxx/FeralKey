# RK98 的 2.4G 接收器研究

核对日期：2026-10-31。**已完成接收器识别与只读状态读取；无线灯光控制尚未打通。** 不能把本记录、设备打开成功或状态读取成功理解为额度灯、通知灯、音乐律动已经支持无线。

## 本机实测

用户确认切至 2.4G 后可以正常打字。仅枚举接收器属性及报告描述符，没有注册输入回调、读取按键内容、发送灯光、改键、配对或固件命令。

- 接收器：Compx `25A7:FA70`，USB `bcdDevice=0391`。这不是经过独立验证的固件版本，且 VID/PID 为共享身份，不能自动确定键盘型号。
- 键盘接口：输入 8 字节、输出 1 字节，无 Feature Report。
- 复合接口：Primary Usage Page `0001` / Usage `0002`，包含 FF01 厂商输入、键盘、媒体与系统集合，以及 FF02 / Usage 2 的 Feature Report `06`；其总长为 8 字节。
- 该复合接口完整报告描述符的 SHA-256 为 `96a6726819c30cb0c4448d629806eba90fd225c3e04f6f9182e789a2aaee6382`。
- 没有发现现有有线适配所用的 65 字节 Feature `0A`，也没有发现下面已知无线协议所用的 20 字节厂商 Output 通道。
- 在允许直接设备访问的环境中，以非独占方式打开接收器，执行三次 `GET_FEATURE 06`，均返回成功、长度 8、同一状态快照。开发执行环境曾以 `0xe00002e2` 拒绝打开；在正常设备访问环境重试成功，因此不能把前一次环境拒绝当作硬件结论。

未知状态字节可能包含配对或其他身份信息，没有解释为电量或协议握手；可分发的诊断默认只输出有效长度与相等性哈希，不输出原始载荷。原始本机证据位于被忽略的 `evidence/wireless-25a7-fa70/`，不进入发布包。

## 已核对的实现与不匹配点

1. [PULSE RK R98 研究](https://github.com/SHISGAY114514/pulse-wireless-battery/blob/e56cf18ffaf471a663453e2b863717d8e0e1bae9/docs/RK_R98_RESEARCH.md) 分析了同 VID/PID 的接收器及 `258A:00C1` 本体，但接收器修订不同。其 Feature `06` 固定状态读取没有获得已验证的灯光或电量控制方式；报告也明确区分键盘 MCU 与无线模块间的内部通信、电脑 USB 通信。
2. [Redragon 控制器的接口筛选](https://github.com/cauanboss/redragon-k629-controller/blob/384aed647e6e553d92b8a16464c2e706fad756f3/backend/device.ts) 虽列出 `25A7:FA70`，实际要求 FF00 厂商接口，发送另一型号的 382 字节颜色报告。本机没有对应接口，不能因编号相同直接移植。
3. [RK 无线灯光实现](https://github.com/shubh-3011/rk-keyboard-software-research/blob/2a5343811efe2ef3dcddc6a63549fe11b170a5d6/rebuild/windows/WirelessLightingReader.cs) 要求 FF02 / Usage 2、20 字节 Input 与 Output。其[实测样本](https://github.com/shubh-3011/rk-keyboard-software-research/blob/2a5343811efe2ef3dcddc6a63549fe11b170a5d6/docs/runtime-evidence/native-wireless-lighting-read-2026-10-26.json) 属于 `258A:0150`，不是这只接收器。
4. [Keylux 的无线协议](https://github.com/SibteProf/keylux/blob/575ef572b5da915aae22551551475904d6a960ec/docs/PROTOCOL.md) 在 AULA `3554:FA09` 上区分了真正的 20 字节 Output 颜色通道与短 Feature 状态通道。它提供了避免误认通道的依据，不能直接当成本机 RK98 的协议。
5. 静态检查 [RK 官方网页驱动](https://drive.rkgaming.com/) 当前入口 `index-Cn9uWLGV.js`，大小 21,153,652 字节、SHA-256 `cf2a6b21c49f2dfdfc9eda178fbd3c9a347163e3e328cf1fddb5631291dffaee`。该入口未找到对应 VID/PID 数字项与 RK98 名称；这只是本次静态检索范围，不证明所有历史驱动或硬件版本都不支持。没有运行官方脚本或分发其资产。

## 可复现操作

在 macOS 源码目录下，只查看接收器接口：

```sh
./scripts/probe-receiver.sh
```

对已核对的 `0391` 修订与完整描述符执行三次只读状态查询：

```sh
./scripts/probe-receiver.sh --read-feature06
```

读取前必须唯一匹配设备编号、USB 连接、用途、8 字节 Feature、`bcdDevice` 及完整描述符哈希。未知版本、多个匹配、异常长度或错误 Report ID 都停止，不尝试其他 ID、其他厂商命令或设置写入。系统拒绝访问时只报告错误，不自动更改权限。

## 接入状态与下一步

源码已能区分「识别到 2.4G 接收器」与「有线控制接口已连接」，并明确无线灯控尚未适配。有线编码器仍只允许精确匹配的 `258A:00C1` 接口；不会把 65 字节数据截断、分割或改头发送到接收器。

要继续实现无线额度灯，需要至少一种可靠依据：能在同型号/修订接收器上实际改变灯效的软件及对应通信样本，或者能明确解释控制通道与颜色命令的接收器协议/固件分析。当前的短状态快照不足以推导颜色命令，也不能证明硬件永远不支持。

此次研究没有刷固件、进入 ISP、重配接收器、模拟按键、枚举未知命令，也没有替换日常使用的应用。研究构建与诊断工具不能当成已经完成无线适配的发行版。

## 验证与产物

- `scripts/test.sh` 通过：773 项额度/协议/发现检查、761 项功能检查，以及模型安全与客户端夹具检查。新增验证覆盖共享接收器识别与有线写入身份隔离、未知描述符/修订拒绝读取、只读识别不打开设备、有线与接收器同时存在时的状态优先级。
- `scripts/probe-receiver.sh --read-feature06` 在本机成功完成三次固定长度读取，未执行设置写入；可复现输出仅包含元数据与载荷哈希。
- 研究构建位于 `build/wireless-research/FeralKey.app`，编译及本地签名校验通过；日常使用的 `build/FeralKey.app` 没有替换。该构建只增加准确识别与状态提示，没有开放无线灯光写入。
