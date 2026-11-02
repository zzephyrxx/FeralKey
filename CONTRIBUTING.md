# 参与 FeralKey

## 开始之前

先阅读[兼容范围](docs/COMPATIBILITY.md)、[技术架构](docs/ARCHITECTURE.md)和[开发指南](docs/DEVELOPMENT.md)。当前没有通用适配器加载机制；新增品牌需要真实协议与代码实现，不能只修改设备编号。

普通问题使用 Issue 模板，附版本、macOS、设备连接方式和可复现步骤；适配资料使用设备模板。安全问题参阅 [SECURITY.md](SECURITY.md)。截图、日志和研究资料需先脱敏。

欢迎贡献键盘适配、已验证的协议证据与界面改进。请先阅读 [键盘探索教程](docs/KEYBOARD-GUIDE.md)，设备不支持也是有效结论。

## 适配贡献

适配贡献需包含精确的设备匹配条件、上游来源与许可证、完整事务编码、无设备测试、实物验证记录，以及未知风险。报告传输必须先检查整个事务，禁止只验证第一包后放行任意后续数据。保持固件、启动加载器与任意原始命令不在写入白名单内。

请勿提交账号凭据、序列号、私人输入、个人额度、驱动安装包或未经许可的固件。新增硬件能力要先区分“公开资料支持”与“已经实物验证”。当前源码采用 GPL-3.0-or-later，参考来源及保留声明见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 提交检查

```sh
python3 scripts/check-repository.py
./scripts/test.sh
./scripts/test-auto-refresh.sh
./scripts/quota-smoke.sh
./scripts/build.sh build/development/FeralKey.app
```

提交清晰的问题说明、相关变更和实际验证结果；不要把格式整理、协议改动和无关功能混进同一个 PR。文档移动应同时更新相对链接和构建资源允许清单。

不要求贡献者必须使用 Windows；目前原生应用仅支持 macOS，其他平台可以复用协议与渲染设计，但需要单独实现设备访问和界面。

修改构建或发布流程后，请额外运行 `python3 tests/PackagingTests.py`。它在无 Git 的临时源码副本中验证递归私密文件排除、原始 logo、旧资源清理与失败构建保留上一份应用；不会访问账号或键盘。两轮代码审查及修复记录位于 `docs/reviews/`。
